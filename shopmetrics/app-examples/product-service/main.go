package main

import (
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/gorilla/mux"
	_ "github.com/lib/pq"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	// HTTP metrics
	httpRequestsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total number of HTTP requests",
		},
		[]string{"method", "path", "status"},
	)

	httpRequestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "HTTP request duration in seconds",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"method", "path"},
	)

	// Business metrics
	productViewsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "product_views_total",
			Help: "Total number of product views",
		},
		[]string{"product_id"},
	)

	productSearchesTotal = promauto.NewCounter(
		prometheus.CounterOpts{
			Name: "product_searches_total",
			Help: "Total number of product searches",
		},
	)

	// Cache metrics
	cacheHitsTotal = promauto.NewCounter(
		prometheus.CounterOpts{
			Name: "cache_hits_total",
			Help: "Total number of cache hits",
		},
	)

	cacheMissesTotal = promauto.NewCounter(
		prometheus.CounterOpts{
			Name: "cache_misses_total",
			Help: "Total number of cache misses",
		},
	)

	// Database metrics
	dbConnectionPoolActive = promauto.NewGauge(
		prometheus.GaugeOpts{
			Name: "database_connection_pool_active",
			Help: "Number of active database connections",
		},
	)

	dbConnectionPoolMax = promauto.NewGauge(
		prometheus.GaugeOpts{
			Name: "database_connection_pool_max",
			Help: "Maximum number of database connections",
		},
	)

	dbQueryDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "database_query_duration_seconds",
			Help: "Database query duration in seconds",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"query_type"},
	)
)

type Product struct {
	ID          string  `json:"id"`
	Name        string  `json:"name"`
	Description string  `json:"description"`
	Price       float64 `json:"price"`
	Stock       int     `json:"stock"`
}

type Server struct {
	db *sql.DB
}

func main() {
	// Connect to database
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgresql://user:password@localhost:5432/products?sslmode=disable"
	}

	db, err := sql.Open("postgres", dbURL)
	if err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer db.Close()

	// Configure connection pool
	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)

	// Update pool metrics
	dbConnectionPoolMax.Set(25)

	// Start metrics updater
	go updateDBMetrics(db)

	server := &Server{db: db}

	// Setup router
	r := mux.NewRouter()
	r.Use(metricsMiddleware)

	// API routes
	r.HandleFunc("/health", server.healthHandler).Methods("GET")
	r.HandleFunc("/ready", server.readyHandler).Methods("GET")
	r.HandleFunc("/products", server.listProductsHandler).Methods("GET")
	r.HandleFunc("/products/{id}", server.getProductHandler).Methods("GET")
	r.HandleFunc("/products/search", server.searchProductsHandler).Methods("GET")

	// Metrics endpoint
	r.Handle("/metrics", promhttp.Handler())

	// Start server
	log.Println("Product Service starting on :8081")
	if err := http.ListenAndServe(":8081", r); err != nil {
		log.Fatal(err)
	}
}

// Middleware to track HTTP metrics
func metricsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		// Wrap response writer to capture status code
		wrapped := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}

		next.ServeHTTP(wrapped, r)

		duration := time.Since(start).Seconds()
		path := r.URL.Path

		httpRequestsTotal.WithLabelValues(r.Method, path, http.StatusText(wrapped.statusCode)).Inc()
		httpRequestDuration.WithLabelValues(r.Method, path).Observe(duration)
	})
}

type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

func (s *Server) healthHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}

func (s *Server) readyHandler(w http.ResponseWriter, r *http.Request) {
	// Check database connection
	if err := s.db.Ping(); err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{"status": "not ready", "error": err.Error()})
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "ready"})
}

func (s *Server) listProductsHandler(w http.ResponseWriter, r *http.Request) {
	start := time.Now()

	rows, err := s.db.Query("SELECT id, name, description, price, stock FROM products LIMIT 100")
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	dbQueryDuration.WithLabelValues("list").Observe(time.Since(start).Seconds())

	var products []Product
	for rows.Next() {
		var p Product
		if err := rows.Scan(&p.ID, &p.Name, &p.Description, &p.Price, &p.Stock); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		products = append(products, p)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(products)
}

func (s *Server) getProductHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	productID := vars["id"]

	// Track product view
	productViewsTotal.WithLabelValues(productID).Inc()

	// Try cache first (simulated)
	if cachedProduct := getFromCache(productID); cachedProduct != nil {
		cacheHitsTotal.Inc()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(cachedProduct)
		return
	}

	cacheMissesTotal.Inc()

	start := time.Now()
	var p Product
	err := s.db.QueryRow(
		"SELECT id, name, description, price, stock FROM products WHERE id = $1",
		productID,
	).Scan(&p.ID, &p.Name, &p.Description, &p.Price, &p.Stock)

	dbQueryDuration.WithLabelValues("get").Observe(time.Since(start).Seconds())

	if err == sql.ErrNoRows {
		http.Error(w, "Product not found", http.StatusNotFound)
		return
	} else if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	// Cache the result (simulated)
	saveToCache(productID, &p)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(p)
}

func (s *Server) searchProductsHandler(w http.ResponseWriter, r *http.Request) {
	productSearchesTotal.Inc()

	query := r.URL.Query().Get("q")
	if query == "" {
		http.Error(w, "Query parameter 'q' is required", http.StatusBadRequest)
		return
	}

	start := time.Now()
	rows, err := s.db.Query(
		"SELECT id, name, description, price, stock FROM products WHERE name ILIKE $1 OR description ILIKE $1 LIMIT 50",
		"%"+query+"%",
	)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	dbQueryDuration.WithLabelValues("search").Observe(time.Since(start).Seconds())

	var products []Product
	for rows.Next() {
		var p Product
		if err := rows.Scan(&p.ID, &p.Name, &p.Description, &p.Price, &p.Stock); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		products = append(products, p)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(products)
}

// Update database connection pool metrics
func updateDBMetrics(db *sql.DB) {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		stats := db.Stats()
		dbConnectionPoolActive.Set(float64(stats.InUse))
	}
}

// Simulated cache functions
var cache = make(map[string]*Product)

func getFromCache(key string) *Product {
	return cache[key]
}

func saveToCache(key string, product *Product) {
	cache[key] = product
}
