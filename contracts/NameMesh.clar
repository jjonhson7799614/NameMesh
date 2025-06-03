
;; title: NameMesh
;; version:
;; summary:
;; description:


(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_NAME_NOT_FOUND (err u101))
(define-constant ERR_NAME_ALREADY_EXISTS (err u102))
(define-constant ERR_INVALID_NAME (err u103))
(define-constant ERR_INSUFFICIENT_PAYMENT (err u104))
(define-constant ERR_NAME_EXPIRED (err u105))
(define-constant ERR_TRANSFER_FAILED (err u106))

(define-constant MIN_NAME_LENGTH u3)
(define-constant MAX_NAME_LENGTH u64)
(define-constant REGISTRATION_COST u1000000)
(define-constant RENEWAL_COST u500000)
(define-constant REGISTRATION_PERIOD u52560)

(define-data-var total-names-registered uint u0)
(define-data-var contract-balance uint u0)

(define-map name-registry
  { name: (string-ascii 64) }
  {
    owner: principal,
    resolver: (string-ascii 256),
    registered-at: uint,
    expires-at: uint,
    transfer-count: uint
  }
)

(define-map name-history
  { name: (string-ascii 64), stacks-block-height: uint }
  {
    previous-owner: principal,
    new-owner: principal,
    action: (string-ascii 32)
  }
)

(define-map user-names
  { user: principal }
  { names: (list 50 (string-ascii 64)) }
)

(define-map resolver-records
  { name: (string-ascii 64), record-type: (string-ascii 16) }
  { value: (string-ascii 256) }
)

(define-private (is-valid-name (name (string-ascii 64)))
  (let ((name-len (len name)))
    (and 
      (>= name-len MIN_NAME_LENGTH)
      (<= name-len MAX_NAME_LENGTH)
      (is-eq (index-of name " ") none)
    )
  )
)

(define-private (is-name-available (name (string-ascii 64)))
  (match (map-get? name-registry { name: name })
    some-entry (< (get expires-at some-entry) stacks-block-height)
    true
  )
)

(define-private (add-name-to-user (user principal) (name (string-ascii 64)))
  (let ((current-names (default-to (list) (get names (map-get? user-names { user: user })))))
    (map-set user-names 
      { user: user }
      { names: (unwrap-panic (as-max-len? (append current-names name) u50)) }
    )
  )
)

(define-private (record-name-history (name (string-ascii 64)) (prev-owner principal) (new-owner principal) (action (string-ascii 32)))
  (map-set name-history
    { name: name, stacks-block-height: stacks-block-height }
    {
      previous-owner: prev-owner,
      new-owner: new-owner,
      action: action
    }
  )
)

(define-public (register-name (name (string-ascii 64)) (resolver (string-ascii 256)))
  (let ((payment-amount (stx-get-balance tx-sender)))
    (asserts! (is-valid-name name) ERR_INVALID_NAME)
    (asserts! (is-name-available name) ERR_NAME_ALREADY_EXISTS)
    (asserts! (>= payment-amount REGISTRATION_COST) ERR_INSUFFICIENT_PAYMENT)
    
    (try! (stx-transfer? REGISTRATION_COST tx-sender (as-contract tx-sender)))
    
    (map-set name-registry
      { name: name }
      {
        owner: tx-sender,
        resolver: resolver,
        registered-at: stacks-block-height,
        expires-at: (+ stacks-block-height REGISTRATION_PERIOD),
        transfer-count: u0
      }
    )
    
    (add-name-to-user tx-sender name)
    (record-name-history name tx-sender tx-sender "register")
    (var-set total-names-registered (+ (var-get total-names-registered) u1))
    (var-set contract-balance (+ (var-get contract-balance) REGISTRATION_COST))
    
    (ok true)
  )
)

(define-public (renew-name (name (string-ascii 64)))
  (let (
    (name-data (unwrap! (map-get? name-registry { name: name }) ERR_NAME_NOT_FOUND))
    (payment-amount (stx-get-balance tx-sender))
  )
    (asserts! (is-eq (get owner name-data) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (>= payment-amount RENEWAL_COST) ERR_INSUFFICIENT_PAYMENT)
    
    (try! (stx-transfer? RENEWAL_COST tx-sender (as-contract tx-sender)))
    
    (map-set name-registry
      { name: name }
      (merge name-data { expires-at: (+ (get expires-at name-data) REGISTRATION_PERIOD) })
    )
    
    (record-name-history name tx-sender tx-sender "renew")
    (var-set contract-balance (+ (var-get contract-balance) RENEWAL_COST))
    
    (ok true)
  )
)

(define-public (transfer-name (name (string-ascii 64)) (new-owner principal))
  (let ((name-data (unwrap! (map-get? name-registry { name: name }) ERR_NAME_NOT_FOUND)))
    (asserts! (is-eq (get owner name-data) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (> (get expires-at name-data) stacks-block-height) ERR_NAME_EXPIRED)
    
    (map-set name-registry
      { name: name }
      (merge name-data { 
        owner: new-owner,
        transfer-count: (+ (get transfer-count name-data) u1)
      })
    )
    
    (add-name-to-user new-owner name)
    (record-name-history name tx-sender new-owner "transfer")
    
    (ok true)
  )
)

(define-public (update-resolver (name (string-ascii 64)) (new-resolver (string-ascii 256)))
  (let ((name-data (unwrap! (map-get? name-registry { name: name }) ERR_NAME_NOT_FOUND)))
    (asserts! (is-eq (get owner name-data) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (> (get expires-at name-data) stacks-block-height) ERR_NAME_EXPIRED)
    
    (map-set name-registry
      { name: name }
      (merge name-data { resolver: new-resolver })
    )
    
    (ok true)
  )
)

(define-public (set-record (name (string-ascii 64)) (record-type (string-ascii 16)) (value (string-ascii 256)))
  (let ((name-data (unwrap! (map-get? name-registry { name: name }) ERR_NAME_NOT_FOUND)))
    (asserts! (is-eq (get owner name-data) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (> (get expires-at name-data) stacks-block-height) ERR_NAME_EXPIRED)
    
    (map-set resolver-records
      { name: name, record-type: record-type }
      { value: value }
    )
    
    (ok true)
  )
)

(define-public (withdraw-funds (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (<= amount (var-get contract-balance)) ERR_INSUFFICIENT_PAYMENT)
    
    (try! (as-contract (stx-transfer? amount tx-sender CONTRACT_OWNER)))
    (var-set contract-balance (- (var-get contract-balance) amount))
    
    (ok true)
  )
)

(define-read-only (get-name-info (name (string-ascii 64)))
  (map-get? name-registry { name: name })
)

(define-read-only (get-name-owner (name (string-ascii 64)))
  (match (map-get? name-registry { name: name })
    some-data (some (get owner some-data))
    none
  )
)

(define-read-only (get-name-resolver (name (string-ascii 64)))
  (match (map-get? name-registry { name: name })
    some-data (some (get resolver some-data))
    none
  )
)

(define-read-only (is-name-expired (name (string-ascii 64)))
  (match (map-get? name-registry { name: name })
    some-data (< (get expires-at some-data) stacks-block-height)
    true
  )
)

(define-read-only (get-user-names (user principal))
  (map-get? user-names { user: user })
)

(define-read-only (get-record (name (string-ascii 64)) (record-type (string-ascii 16)))
  (map-get? resolver-records { name: name, record-type: record-type })
)

(define-read-only (get-name-history (name (string-ascii 64)) (stacks-block-height-param uint))
  (map-get? name-history { name: name, stacks-block-height: stacks-block-height-param })
)

(define-read-only (get-total-names)
  (var-get total-names-registered)
)

(define-read-only (get-contract-balance)
  (var-get contract-balance)
)

(define-read-only (get-registration-cost)
  REGISTRATION_COST
)

(define-read-only (get-renewal-cost)
  RENEWAL_COST
)