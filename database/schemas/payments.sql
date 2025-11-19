-- Payments Database Schema

-- Payment methods table
CREATE TABLE IF NOT EXISTS payment_methods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    type VARCHAR(50) NOT NULL CHECK (type IN ('card', 'paypal', 'bank_account', 'wallet')),
    provider VARCHAR(50) NOT NULL,
    is_default BOOLEAN DEFAULT FALSE,
    -- Card details (tokenized)
    card_last4 VARCHAR(4),
    card_brand VARCHAR(20),
    card_exp_month INTEGER,
    card_exp_year INTEGER,
    card_fingerprint VARCHAR(255),
    -- PayPal details
    paypal_email VARCHAR(255),
    -- Bank account details (tokenized)
    bank_name VARCHAR(100),
    bank_account_last4 VARCHAR(4),
    bank_routing_number VARCHAR(20),
    -- Billing address
    billing_address_id UUID,
    -- Metadata
    metadata JSONB,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_payment_methods_user_id ON payment_methods(user_id);
CREATE INDEX idx_payment_methods_type ON payment_methods(type);

-- Transactions table
CREATE TABLE IF NOT EXISTS transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_number VARCHAR(50) UNIQUE NOT NULL,
    order_id UUID NOT NULL,
    user_id UUID NOT NULL,
    payment_method_id UUID REFERENCES payment_methods(id),
    type VARCHAR(50) NOT NULL CHECK (type IN ('charge', 'refund', 'authorization', 'capture')),
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    amount DECIMAL(10, 2) NOT NULL CHECK (amount >= 0),
    currency VARCHAR(3) NOT NULL DEFAULT 'USD',
    provider VARCHAR(50) NOT NULL,
    provider_transaction_id VARCHAR(255),
    provider_response JSONB,
    failure_code VARCHAR(100),
    failure_message TEXT,
    metadata JSONB,
    processed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_transactions_transaction_number ON transactions(transaction_number);
CREATE INDEX idx_transactions_order_id ON transactions(order_id);
CREATE INDEX idx_transactions_user_id ON transactions(user_id);
CREATE INDEX idx_transactions_status ON transactions(status);
CREATE INDEX idx_transactions_type ON transactions(type);
CREATE INDEX idx_transactions_created_at ON transactions(created_at);

-- Refunds table
CREATE TABLE IF NOT EXISTS refunds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    refund_number VARCHAR(50) UNIQUE NOT NULL,
    transaction_id UUID REFERENCES transactions(id) ON DELETE CASCADE,
    order_id UUID NOT NULL,
    amount DECIMAL(10, 2) NOT NULL CHECK (amount > 0),
    currency VARCHAR(3) NOT NULL DEFAULT 'USD',
    reason VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    provider VARCHAR(50) NOT NULL,
    provider_refund_id VARCHAR(255),
    provider_response JSONB,
    failure_code VARCHAR(100),
    failure_message TEXT,
    processed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_refunds_refund_number ON refunds(refund_number);
CREATE INDEX idx_refunds_transaction_id ON refunds(transaction_id);
CREATE INDEX idx_refunds_order_id ON refunds(order_id);
CREATE INDEX idx_refunds_status ON refunds(status);

-- Payment attempts log (for fraud detection)
CREATE TABLE IF NOT EXISTS payment_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL,
    user_id UUID NOT NULL,
    payment_method_id UUID,
    amount DECIMAL(10, 2) NOT NULL,
    currency VARCHAR(3) NOT NULL,
    status VARCHAR(50) NOT NULL,
    ip_address INET,
    user_agent TEXT,
    failure_code VARCHAR(100),
    failure_message TEXT,
    risk_score DECIMAL(5, 2),
    metadata JSONB,
    attempted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_payment_attempts_order_id ON payment_attempts(order_id);
CREATE INDEX idx_payment_attempts_user_id ON payment_attempts(user_id);
CREATE INDEX idx_payment_attempts_attempted_at ON payment_attempts(attempted_at);
CREATE INDEX idx_payment_attempts_status ON payment_attempts(status);

-- Wallet/Balance table (for store credit, gift cards)
CREATE TABLE IF NOT EXISTS wallets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL,
    balance DECIMAL(10, 2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
    currency VARCHAR(3) NOT NULL DEFAULT 'USD',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_wallets_user_id ON wallets(user_id);

-- Wallet transactions table
CREATE TABLE IF NOT EXISTS wallet_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL CHECK (type IN ('credit', 'debit')),
    amount DECIMAL(10, 2) NOT NULL CHECK (amount > 0),
    balance_after DECIMAL(10, 2) NOT NULL,
    reference_type VARCHAR(50),
    reference_id UUID,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_wallet_transactions_wallet_id ON wallet_transactions(wallet_id);
CREATE INDEX idx_wallet_transactions_created_at ON wallet_transactions(created_at);

-- Gift cards table
CREATE TABLE IF NOT EXISTS gift_cards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(50) UNIQUE NOT NULL,
    initial_balance DECIMAL(10, 2) NOT NULL CHECK (initial_balance > 0),
    current_balance DECIMAL(10, 2) NOT NULL CHECK (current_balance >= 0),
    currency VARCHAR(3) NOT NULL DEFAULT 'USD',
    purchaser_user_id UUID,
    recipient_email VARCHAR(255),
    recipient_user_id UUID,
    message TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    redeemed_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_gift_cards_code ON gift_cards(code);
CREATE INDEX idx_gift_cards_recipient_user_id ON gift_cards(recipient_user_id);

-- Gift card usage tracking
CREATE TABLE IF NOT EXISTS gift_card_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gift_card_id UUID REFERENCES gift_cards(id) ON DELETE CASCADE,
    order_id UUID NOT NULL,
    amount_used DECIMAL(10, 2) NOT NULL CHECK (amount_used > 0),
    balance_after DECIMAL(10, 2) NOT NULL,
    used_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_gift_card_usage_gift_card_id ON gift_card_usage(gift_card_id);
CREATE INDEX idx_gift_card_usage_order_id ON gift_card_usage(order_id);

-- Payment gateway configuration (for multi-provider support)
CREATE TABLE IF NOT EXISTS payment_gateways (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    provider VARCHAR(50) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    is_default BOOLEAN DEFAULT FALSE,
    supported_currencies TEXT[],
    supported_payment_methods TEXT[],
    config JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Function to generate transaction number
CREATE OR REPLACE FUNCTION generate_transaction_number()
RETURNS TRIGGER AS $$
BEGIN
    NEW.transaction_number := 'TXN-' || TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDD') || '-' || LPAD(nextval('transaction_number_seq')::TEXT, 8, '0');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql();

-- Sequence for transaction numbers
CREATE SEQUENCE IF NOT EXISTS transaction_number_seq;

-- Trigger to auto-generate transaction number
CREATE TRIGGER generate_transaction_number_trigger
    BEFORE INSERT ON transactions
    FOR EACH ROW
    WHEN (NEW.transaction_number IS NULL)
    EXECUTE FUNCTION generate_transaction_number();

-- Function to generate refund number
CREATE OR REPLACE FUNCTION generate_refund_number()
RETURNS TRIGGER AS $$
BEGIN
    NEW.refund_number := 'REF-' || TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDD') || '-' || LPAD(nextval('refund_number_seq')::TEXT, 8, '0');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Sequence for refund numbers
CREATE SEQUENCE IF NOT EXISTS refund_number_seq;

-- Trigger to auto-generate refund number
CREATE TRIGGER generate_refund_number_trigger
    BEFORE INSERT ON refunds
    FOR EACH ROW
    WHEN (NEW.refund_number IS NULL)
    EXECUTE FUNCTION generate_refund_number();

-- Triggers for updated_at
CREATE TRIGGER update_payment_methods_updated_at BEFORE UPDATE ON payment_methods
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_transactions_updated_at BEFORE UPDATE ON transactions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_refunds_updated_at BEFORE UPDATE ON refunds
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_wallets_updated_at BEFORE UPDATE ON wallets
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_payment_gateways_updated_at BEFORE UPDATE ON payment_gateways
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
