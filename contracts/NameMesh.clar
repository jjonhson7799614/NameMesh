
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
(define-constant ERR_AUCTION_NOT_FOUND (err u107))
(define-constant ERR_AUCTION_ENDED (err u108))
(define-constant ERR_BID_TOO_LOW (err u109))
(define-constant ERR_AUCTION_ACTIVE (err u110))
(define-constant ERR_NOT_AUCTION_WINNER (err u111))
(define-constant ERR_AUCTION_NOT_ENDED (err u112))
(define-constant ERR_SUBDOMAIN_EXISTS (err u113))
(define-constant ERR_INVALID_SUBDOMAIN (err u114))
(define-constant ERR_NOT_PARENT_OWNER (err u115))
(define-constant ERR_SUBDOMAIN_NOT_FOUND (err u116))
(define-constant ERR_NOT_SUBDOMAIN_OWNER (err u117))
(define-constant ERR_PARENT_NAME_EXPIRED (err u118))

(define-constant MIN_NAME_LENGTH u3)
(define-constant MAX_NAME_LENGTH u64)
(define-constant REGISTRATION_COST u1000000)
(define-constant RENEWAL_COST u500000)
(define-constant REGISTRATION_PERIOD u52560)
(define-constant AUCTION_DURATION u1440)
(define-constant MIN_BID_INCREMENT u100000)
(define-constant AUCTION_GRACE_PERIOD u144)
(define-constant DEFAULT_SUBDOMAIN_COST u250000)
(define-constant MAX_SUBDOMAIN_LENGTH u32)
(define-constant SUBDOMAIN_REVENUE_SHARE u70)

(define-data-var total-names-registered uint u0)
(define-data-var total-subdomains-created uint u0)
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

(define-map name-auctions
  { name: (string-ascii 64) }
  {
    start-block: uint,
    end-block: uint,
    current-bid: uint,
    highest-bidder: principal,
    bid-count: uint,
    status: (string-ascii 16)
  }
)

(define-map auction-bids
  { name: (string-ascii 64), bidder: principal, bid-block: uint }
  {
    bid-amount: uint,
    refunded: bool
  }
)

(define-map user-auction-bids
  { user: principal }
  { active-bids: (list 20 (string-ascii 64)) }
)

(define-map subdomain-registry
  { parent-name: (string-ascii 64), subdomain: (string-ascii 32) }
  {
    owner: principal,
    delegated-to: principal,
    resolver: (string-ascii 256),
    created-at: uint,
    cost: uint,
    revenue-share: uint
  }
)

(define-map parent-subdomain-settings
  { parent-name: (string-ascii 64) }
  {
    subdomain-cost: uint,
    revenue-share: uint,
    max-subdomains: uint,
    current-subdomains: uint,
    allow-delegation: bool
  }
)

(define-map user-subdomains
  { user: principal }
  { subdomains: (list 30 {parent: (string-ascii 64), sub: (string-ascii 32)}) }
)

(define-map subdomain-records
  { parent-name: (string-ascii 64), subdomain: (string-ascii 32), record-type: (string-ascii 16) }
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
    some-entry (and 
      (< (get expires-at some-entry) stacks-block-height)
      (is-none (map-get? name-auctions { name: name }))
    )
    true
  )
)

(define-private (is-auction-active (name (string-ascii 64)))
  (match (map-get? name-auctions { name: name })
    some-auction (and 
      (is-eq (get status some-auction) "active")
      (< stacks-block-height (get end-block some-auction))
    )
    false
  )
)

(define-private (add-bid-to-user (user principal) (name (string-ascii 64)))
  (let ((current-bids (default-to (list) (get active-bids (map-get? user-auction-bids { user: user })))))
    (map-set user-auction-bids 
      { user: user }
      { active-bids: (unwrap-panic (as-max-len? (append current-bids name) u20)) }
    )
  )
)

(define-private (is-valid-subdomain (subdomain (string-ascii 32)))
  (let ((subdomain-len (len subdomain)))
    (and 
      (>= subdomain-len u1)
      (<= subdomain-len MAX_SUBDOMAIN_LENGTH)
      (is-eq (index-of subdomain " ") none)
      (is-eq (index-of subdomain ".") none)
    )
  )
)

(define-private (add-subdomain-to-user (user principal) (parent-name (string-ascii 64)) (subdomain (string-ascii 32)))
  (let ((current-subdomains (default-to (list) (get subdomains (map-get? user-subdomains { user: user })))))
    (map-set user-subdomains 
      { user: user }
      { subdomains: (unwrap-panic (as-max-len? (append current-subdomains {parent: parent-name, sub: subdomain}) u30)) }
    )
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

(define-public (start-auction (name (string-ascii 64)))
  (let ((name-data (map-get? name-registry { name: name })))
    (asserts! (is-valid-name name) ERR_INVALID_NAME)
    (asserts! (is-some name-data) ERR_NAME_NOT_FOUND)
    (asserts! (< (get expires-at (unwrap-panic name-data)) (+ stacks-block-height AUCTION_GRACE_PERIOD)) ERR_NAME_NOT_FOUND)
    (asserts! (is-none (map-get? name-auctions { name: name })) ERR_AUCTION_ACTIVE)
    
    (map-set name-auctions
      { name: name }
      {
        start-block: stacks-block-height,
        end-block: (+ stacks-block-height AUCTION_DURATION),
        current-bid: u0,
        highest-bidder: tx-sender,
        bid-count: u0,
        status: "active"
      }
    )
    
    (record-name-history name (get owner (unwrap-panic name-data)) tx-sender "auction-start")
    
    (ok true)
  )
)

(define-public (place-bid (name (string-ascii 64)) (bid-amount uint))
  (let (
    (auction-data (unwrap! (map-get? name-auctions { name: name }) ERR_AUCTION_NOT_FOUND))
    (payment-amount (stx-get-balance tx-sender))
  )
    (asserts! (is-auction-active name) ERR_AUCTION_ENDED)
    (asserts! (>= payment-amount bid-amount) ERR_INSUFFICIENT_PAYMENT)
    (asserts! (> bid-amount (+ (get current-bid auction-data) MIN_BID_INCREMENT)) ERR_BID_TOO_LOW)
    
    (try! (stx-transfer? bid-amount tx-sender (as-contract tx-sender)))
    
    (map-set auction-bids
      { name: name, bidder: tx-sender, bid-block: stacks-block-height }
      {
        bid-amount: bid-amount,
        refunded: false
      }
    )
    
    (map-set name-auctions
      { name: name }
      (merge auction-data {
        current-bid: bid-amount,
        highest-bidder: tx-sender,
        bid-count: (+ (get bid-count auction-data) u1)
      })
    )
    
    (add-bid-to-user tx-sender name)
    (var-set contract-balance (+ (var-get contract-balance) bid-amount))
    
    (ok true)
  )
)

(define-public (finalize-auction (name (string-ascii 64)))
  (let ((auction-data (unwrap! (map-get? name-auctions { name: name }) ERR_AUCTION_NOT_FOUND)))
    (asserts! (>= stacks-block-height (get end-block auction-data)) ERR_AUCTION_NOT_ENDED)
    (asserts! (is-eq (get status auction-data) "active") ERR_AUCTION_ENDED)
    
    (if (> (get current-bid auction-data) u0)
      (begin
        (map-set name-registry
          { name: name }
          {
            owner: (get highest-bidder auction-data),
            resolver: "",
            registered-at: stacks-block-height,
            expires-at: (+ stacks-block-height REGISTRATION_PERIOD),
            transfer-count: u0
          }
        )
        (add-name-to-user (get highest-bidder auction-data) name)
        (record-name-history name CONTRACT_OWNER (get highest-bidder auction-data) "auction-win")
      )
      true
    )
    
    (map-set name-auctions
      { name: name }
      (merge auction-data { status: "ended" })
    )
    
    (ok true)
  )
)

(define-public (refund-losing-bid (name (string-ascii 64)) (bidder principal) (bid-block uint))
  (let (
    (bid-data (unwrap! (map-get? auction-bids { name: name, bidder: bidder, bid-block: bid-block }) ERR_AUCTION_NOT_FOUND))
    (auction-data (unwrap! (map-get? name-auctions { name: name }) ERR_AUCTION_NOT_FOUND))
  )
    (asserts! (is-eq (get status auction-data) "ended") ERR_AUCTION_NOT_ENDED)
    (asserts! (not (is-eq bidder (get highest-bidder auction-data))) ERR_NOT_AUCTION_WINNER)
    (asserts! (not (get refunded bid-data)) ERR_TRANSFER_FAILED)
    
    (try! (as-contract (stx-transfer? (get bid-amount bid-data) tx-sender bidder)))
    
    (map-set auction-bids
      { name: name, bidder: bidder, bid-block: bid-block }
      (merge bid-data { refunded: true })
    )
    
    (var-set contract-balance (- (var-get contract-balance) (get bid-amount bid-data)))
    
    (ok true)
  )
)

(define-public (configure-subdomain-settings (parent-name (string-ascii 64)) (subdomain-cost uint) (revenue-share uint) (max-subdomains uint) (allow-delegation bool))
  (let ((name-data (unwrap! (map-get? name-registry { name: parent-name }) ERR_NAME_NOT_FOUND)))
    (asserts! (is-eq (get owner name-data) tx-sender) ERR_NOT_PARENT_OWNER)
    (asserts! (> (get expires-at name-data) stacks-block-height) ERR_PARENT_NAME_EXPIRED)
    (asserts! (<= revenue-share u100) ERR_INVALID_SUBDOMAIN)
    
    (map-set parent-subdomain-settings
      { parent-name: parent-name }
      {
        subdomain-cost: subdomain-cost,
        revenue-share: revenue-share,
        max-subdomains: max-subdomains,
        current-subdomains: u0,
        allow-delegation: allow-delegation
      }
    )
    
    (ok true)
  )
)

(define-public (create-subdomain (parent-name (string-ascii 64)) (subdomain (string-ascii 32)) (resolver (string-ascii 256)))
  (let (
    (name-data (unwrap! (map-get? name-registry { name: parent-name }) ERR_NAME_NOT_FOUND))
    (settings (unwrap! (map-get? parent-subdomain-settings { parent-name: parent-name }) ERR_INVALID_SUBDOMAIN))
    (subdomain-cost (get subdomain-cost settings))
    (payment-amount (stx-get-balance tx-sender))
  )
    (asserts! (is-valid-subdomain subdomain) ERR_INVALID_SUBDOMAIN)
    (asserts! (> (get expires-at name-data) stacks-block-height) ERR_PARENT_NAME_EXPIRED)
    (asserts! (is-none (map-get? subdomain-registry { parent-name: parent-name, subdomain: subdomain })) ERR_SUBDOMAIN_EXISTS)
    (asserts! (< (get current-subdomains settings) (get max-subdomains settings)) ERR_INVALID_SUBDOMAIN)
    (asserts! (>= payment-amount subdomain-cost) ERR_INSUFFICIENT_PAYMENT)
    
    (try! (stx-transfer? subdomain-cost tx-sender (as-contract tx-sender)))
    
    (let (
      (parent-owner-share (/ (* subdomain-cost (get revenue-share settings)) u100))
      (contract-share (- subdomain-cost parent-owner-share))
    )
      (if (> parent-owner-share u0)
        (try! (as-contract (stx-transfer? parent-owner-share tx-sender (get owner name-data))))
        true
      )
      
      (map-set subdomain-registry
        { parent-name: parent-name, subdomain: subdomain }
        {
          owner: (get owner name-data),
          delegated-to: tx-sender,
          resolver: resolver,
          created-at: stacks-block-height,
          cost: subdomain-cost,
          revenue-share: (get revenue-share settings)
        }
      )
      
      (map-set parent-subdomain-settings
        { parent-name: parent-name }
        (merge settings { current-subdomains: (+ (get current-subdomains settings) u1) })
      )
      
      (add-subdomain-to-user tx-sender parent-name subdomain)
      (var-set total-subdomains-created (+ (var-get total-subdomains-created) u1))
      (var-set contract-balance (+ (var-get contract-balance) contract-share))
      
      (ok true)
    )
  )
)

(define-public (transfer-subdomain (parent-name (string-ascii 64)) (subdomain (string-ascii 32)) (new-delegated principal))
  (let ((subdomain-data (unwrap! (map-get? subdomain-registry { parent-name: parent-name, subdomain: subdomain }) ERR_SUBDOMAIN_NOT_FOUND)))
    (asserts! (is-eq (get delegated-to subdomain-data) tx-sender) ERR_NOT_SUBDOMAIN_OWNER)
    
    (map-set subdomain-registry
      { parent-name: parent-name, subdomain: subdomain }
      (merge subdomain-data { delegated-to: new-delegated })
    )
    
    (add-subdomain-to-user new-delegated parent-name subdomain)
    
    (ok true)
  )
)

(define-public (set-subdomain-record (parent-name (string-ascii 64)) (subdomain (string-ascii 32)) (record-type (string-ascii 16)) (value (string-ascii 256)))
  (let ((subdomain-data (unwrap! (map-get? subdomain-registry { parent-name: parent-name, subdomain: subdomain }) ERR_SUBDOMAIN_NOT_FOUND)))
    (asserts! (is-eq (get delegated-to subdomain-data) tx-sender) ERR_NOT_SUBDOMAIN_OWNER)
    
    (map-set subdomain-records
      { parent-name: parent-name, subdomain: subdomain, record-type: record-type }
      { value: value }
    )
    
    (ok true)
  )
)

(define-public (update-subdomain-resolver (parent-name (string-ascii 64)) (subdomain (string-ascii 32)) (new-resolver (string-ascii 256)))
  (let ((subdomain-data (unwrap! (map-get? subdomain-registry { parent-name: parent-name, subdomain: subdomain }) ERR_SUBDOMAIN_NOT_FOUND)))
    (asserts! (is-eq (get delegated-to subdomain-data) tx-sender) ERR_NOT_SUBDOMAIN_OWNER)
    
    (map-set subdomain-registry
      { parent-name: parent-name, subdomain: subdomain }
      (merge subdomain-data { resolver: new-resolver })
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

(define-read-only (get-auction-info (name (string-ascii 64)))
  (map-get? name-auctions { name: name })
)

(define-read-only (get-auction-bid (name (string-ascii 64)) (bidder principal) (bid-block uint))
  (map-get? auction-bids { name: name, bidder: bidder, bid-block: bid-block })
)

(define-read-only (get-user-auction-bids (user principal))
  (map-get? user-auction-bids { user: user })
)

(define-read-only (is-auction-ended (name (string-ascii 64)))
  (match (map-get? name-auctions { name: name })
    some-auction (>= stacks-block-height (get end-block some-auction))
    false
  )
)

(define-read-only (get-auction-winner (name (string-ascii 64)))
  (match (map-get? name-auctions { name: name })
    some-auction (if (is-eq (get status some-auction) "ended")
      (some (get highest-bidder some-auction))
      none
    )
    none
  )
)

(define-read-only (get-auction-time-remaining (name (string-ascii 64)))
  (match (map-get? name-auctions { name: name })
    some-auction (if (> (get end-block some-auction) stacks-block-height)
      (some (- (get end-block some-auction) stacks-block-height))
      (some u0)
    )
    none
  )
)

(define-read-only (get-subdomain-info (parent-name (string-ascii 64)) (subdomain (string-ascii 32)))
  (map-get? subdomain-registry { parent-name: parent-name, subdomain: subdomain })
)

(define-read-only (get-parent-subdomain-settings (parent-name (string-ascii 64)))
  (map-get? parent-subdomain-settings { parent-name: parent-name })
)

(define-read-only (get-user-subdomains (user principal))
  (map-get? user-subdomains { user: user })
)

(define-read-only (get-subdomain-record (parent-name (string-ascii 64)) (subdomain (string-ascii 32)) (record-type (string-ascii 16)))
  (map-get? subdomain-records { parent-name: parent-name, subdomain: subdomain, record-type: record-type })
)

(define-read-only (get-total-subdomains)
  (var-get total-subdomains-created)
)

(define-read-only (is-subdomain-available (parent-name (string-ascii 64)) (subdomain (string-ascii 32)))
  (is-none (map-get? subdomain-registry { parent-name: parent-name, subdomain: subdomain }))
)

(define-read-only (get-subdomain-owner (parent-name (string-ascii 64)) (subdomain (string-ascii 32)))
  (match (map-get? subdomain-registry { parent-name: parent-name, subdomain: subdomain })
    some-data (some (get delegated-to some-data))
    none
  )
)

(define-read-only (get-subdomain-cost-for-parent (parent-name (string-ascii 64)))
  (match (map-get? parent-subdomain-settings { parent-name: parent-name })
    some-settings (some (get subdomain-cost some-settings))
    (some DEFAULT_SUBDOMAIN_COST)
  )
)





