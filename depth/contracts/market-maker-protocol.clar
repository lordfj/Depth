;; Market Maker Protocol
;; Version 2: Market-focused terminology and structure

;; Market Authority
(define-constant market-controller tx-sender)
(define-constant market-error-access-denied (err u300))
(define-constant market-error-low-reserves (err u301))
(define-constant market-error-invalid-order (err u302))
(define-constant market-error-price-impact (err u303))
(define-constant market-error-asset-type (err u304))
(define-constant market-error-execution-failed (err u305))
(define-constant market-error-market-exists (err u306))
(define-constant market-error-no-market (err u307))

;; Market Reserves
(define-data-var base-asset-balance uint u0)
(define-data-var quote-asset-balance uint u0)
(define-data-var market-share-tokens uint u0)
(define-data-var market-active bool false)

;; Quote Asset Contract
(define-data-var quote-asset-contract principal .token)

;; Market Participant Holdings
(define-map participant-holdings principal uint)

;; Order Execution Records
(define-map execution-log 
  { order-id: uint }
  { 
    participant: principal,
    base-sold: uint,
    quote-bought: uint,
    base-bought: uint,
    quote-sold: uint,
    block-number: uint
  }
)

(define-data-var order-sequence uint u0)

;; Asset Transfer Interface
(define-trait tradeable-asset
  (
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    (get-name () (response (string-ascii 32) uint))
    (get-symbol () (response (string-ascii 32) uint))
    (get-decimals () (response uint uint))
    (get-balance (principal) (response uint uint))
    (get-total-supply () (response uint uint))
    (get-token-uri () (response (optional (string-utf8 256)) uint))
  )
)

;; Mathematical Helpers

;; Return lesser value
(define-private (lesser-of (a uint) (b uint))
  (if (< a b) a b))

;; Market Information Functions

(define-read-only (get-market-depth)
  {
    base-depth: (var-get base-asset-balance),
    quote-depth: (var-get quote-asset-balance)
  }
)

(define-read-only (get-participant-position (participant principal))
  (default-to u0 (map-get? participant-holdings participant))
)

(define-read-only (get-outstanding-shares)
  (var-get market-share-tokens)
)

(define-read-only (is-market-active)
  (var-get market-active)
)

(define-read-only (get-quote-asset-address)
  (var-get quote-asset-contract)
)

;; Price Discovery Functions (0.3% trading fee)
(define-read-only (price-quote (sell-amount uint) (sell-reserve uint) (buy-reserve uint))
  (if (or (is-eq sell-amount u0) (is-eq sell-reserve u0) (is-eq buy-reserve u0))
    u0
    (let (
      (net-sell-amount (* sell-amount u997))
      (price-numerator (* net-sell-amount buy-reserve))
      (price-denominator (+ (* sell-reserve u1000) net-sell-amount))
    )
    (/ price-numerator price-denominator)))
)

(define-read-only (reverse-price-quote (buy-amount uint) (sell-reserve uint) (buy-reserve uint))
  (if (or (is-eq buy-amount u0) (is-eq sell-reserve u0) (is-eq buy-reserve u0))
    u0
    (let (
      (price-numerator (* (* sell-reserve buy-amount) u1000))
      (price-denominator (* (- buy-reserve buy-amount) u997))
    )
    (+ (/ price-numerator price-denominator) u1)))
)

(define-read-only (liquidity-value (asset-amount uint) (asset-reserve uint) (paired-reserve uint))
  (if (is-eq asset-reserve u0)
    u0
    (/ (* asset-amount paired-reserve) asset-reserve))
)

;; Market Operations

(define-public (create-market (asset-interface <tradeable-asset>) (base-deposit uint) (quote-deposit uint))
  (let (
    (initial-shares (lesser-of base-deposit quote-deposit))
  )
    (asserts! (not (var-get market-active)) market-error-market-exists)
    (asserts! (> base-deposit u0) market-error-invalid-order)
    (asserts! (> quote-deposit u0) market-error-invalid-order)
    (asserts! (> initial-shares u0) market-error-low-reserves)
    
    (var-set quote-asset-contract (contract-of asset-interface))
    
    (try! (contract-call? asset-interface transfer quote-deposit tx-sender (as-contract tx-sender) none))
    
    (var-set base-asset-balance base-deposit)
    (var-set quote-asset-balance quote-deposit)
    (var-set market-share-tokens initial-shares)
    (var-set market-active true)
    
    (map-set participant-holdings tx-sender initial-shares)
    
    (ok initial-shares)
  )
)

(define-public (provide-liquidity (asset-interface <tradeable-asset>) (base-amount uint) (quote-amount uint) (min-shares uint))
  (let (
    (existing-base-balance (var-get base-asset-balance))
    (existing-quote-balance (var-get quote-asset-balance))
    (existing-share-supply (var-get market-share-tokens))
    (new-shares (lesser-of 
                 (/ (* base-amount existing-share-supply) existing-base-balance)
                 (/ (* quote-amount existing-share-supply) existing-quote-balance)))
    (current-position (get-participant-position tx-sender))
  )
    (asserts! (var-get market-active) market-error-no-market)
    (asserts! (is-eq (contract-of asset-interface) (var-get quote-asset-contract)) market-error-asset-type)
    (asserts! (> base-amount u0) market-error-invalid-order)
    (asserts! (> quote-amount u0) market-error-invalid-order)
    (asserts! (>= new-shares min-shares) market-error-price-impact)
    
    (try! (contract-call? asset-interface transfer quote-amount tx-sender (as-contract tx-sender) none))
    
    (var-set base-asset-balance (+ existing-base-balance base-amount))
    (var-set quote-asset-balance (+ existing-quote-balance quote-amount))
    (var-set market-share-tokens (+ existing-share-supply new-shares))
    
    (map-set participant-holdings tx-sender (+ current-position new-shares))
    
    (ok new-shares)
  )
)

(define-public (redeem-liquidity (asset-interface <tradeable-asset>) (shares-amount uint) (min-base uint) (min-quote uint))
  (let (
    (existing-base-balance (var-get base-asset-balance))
    (existing-quote-balance (var-get quote-asset-balance))
    (existing-share-supply (var-get market-share-tokens))
    (current-position (get-participant-position tx-sender))
    (base-redemption (/ (* shares-amount existing-base-balance) existing-share-supply))
    (quote-redemption (/ (* shares-amount existing-quote-balance) existing-share-supply))
  )
    (asserts! (var-get market-active) market-error-no-market)
    (asserts! (is-eq (contract-of asset-interface) (var-get quote-asset-contract)) market-error-asset-type)
    (asserts! (> shares-amount u0) market-error-invalid-order)
    (asserts! (>= current-position shares-amount) market-error-low-reserves)
    (asserts! (>= base-redemption min-base) market-error-price-impact)
    (asserts! (>= quote-redemption min-quote) market-error-price-impact)
    
    (var-set base-asset-balance (- existing-base-balance base-redemption))
    (var-set quote-asset-balance (- existing-quote-balance quote-redemption))
    (var-set market-share-tokens (- existing-share-supply shares-amount))
    
    (map-set participant-holdings tx-sender (- current-position shares-amount))
    
    (try! (as-contract (stx-transfer? base-redemption tx-sender tx-sender)))
    (try! (as-contract (contract-call? asset-interface transfer quote-redemption tx-sender tx-sender none)))
    
    (ok { base: base-redemption, quote: quote-redemption })
  )
)

(define-public (market-sell-base (asset-interface <tradeable-asset>) (base-sell-amount uint) (min-quote-receive uint))
  (let (
    (existing-base-balance (var-get base-asset-balance))
    (existing-quote-balance (var-get quote-asset-balance))
    (quote-received (price-quote base-sell-amount existing-base-balance existing-quote-balance))
    (execution-id (var-get order-sequence))
  )
    (asserts! (var-get market-active) market-error-no-market)
    (asserts! (is-eq (contract-of asset-interface) (var-get quote-asset-contract)) market-error-asset-type)
    (asserts! (> base-sell-amount u0) market-error-invalid-order)
    (asserts! (>= quote-received min-quote-receive) market-error-price-impact)
    (asserts! (< quote-received existing-quote-balance) market-error-low-reserves)
    
    (var-set base-asset-balance (+ existing-base-balance base-sell-amount))
    (var-set quote-asset-balance (- existing-quote-balance quote-received))
    
    (try! (as-contract (contract-call? asset-interface transfer quote-received tx-sender tx-sender none)))
    
    (map-set execution-log 
      { order-id: execution-id }
      { 
        participant: tx-sender,
        base-sold: base-sell-amount,
        quote-bought: quote-received,
        base-bought: u0,
        quote-sold: u0,
        block-number: block-height
      }
    )
    (var-set order-sequence (+ execution-id u1))
    
    (ok quote-received)
  )
)

(define-public (market-buy-base (asset-interface <tradeable-asset>) (quote-sell-amount uint) (min-base-receive uint))
  (let (
    (existing-base-balance (var-get base-asset-balance))
    (existing-quote-balance (var-get quote-asset-balance))
    (base-received (price-quote quote-sell-amount existing-quote-balance existing-base-balance))
    (execution-id (var-get order-sequence))
  )
    (asserts! (var-get market-active) market-error-no-market)
    (asserts! (is-eq (contract-of asset-interface) (var-get quote-asset-contract)) market-error-asset-type)
    (asserts! (> quote-sell-amount u0) market-error-invalid-order)
    (asserts! (>= base-received min-base-receive) market-error-price-impact)
    (asserts! (< base-received existing-base-balance) market-error-low-reserves)
    
    (try! (contract-call? asset-interface transfer quote-sell-amount tx-sender (as-contract tx-sender) none))
    
    (var-set base-asset-balance (- existing-base-balance base-received))
    (var-set quote-asset-balance (+ existing-quote-balance quote-sell-amount))
    
    (try! (as-contract (stx-transfer? base-received tx-sender tx-sender)))
    
    (map-set execution-log 
      { order-id: execution-id }
      { 
        participant: tx-sender,
        base-sold: u0,
        quote-bought: u0,
        base-bought: base-received,
        quote-sold: quote-sell-amount,
        block-number: block-height
      }
    )
    (var-set order-sequence (+ execution-id u1))
    
    (ok base-received)
  )
)