;; NameMesh Reputation & Trust System
;; Tracks name trustworthiness through community feedback and usage metrics

(define-constant BPS u10000)
(define-constant MAX_REPUTATION u10000)
(define-constant MIN_FEEDBACK_STAKE u100000) ;; 0.1 STX to prevent spam
(define-constant INITIAL_REPUTATION u5000) ;; 50% starting reputation
(define-constant REPUTATION_DECAY_RATE u50) ;; 0.5% per period
(define-constant MAX_FEEDBACK_WEIGHT u1000) ;; 10x multiplier for high-stake feedback

(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_INVALID_NAME (err u201))
(define-constant ERR_INSUFFICIENT_STAKE (err u202))
(define-constant ERR_ALREADY_RATED (err u203))
(define-constant ERR_SELF_RATING (err u204))
(define-constant ERR_INVALID_RATING (err u205))

;; Only authorized contract can update technical metrics
(define-data-var authorized-contract (optional principal) none)

;; Maps for reputation data
(define-map name-reputation
  { name: (string-ascii 64) }
  {
    overall-score: uint,
    technical-score: uint,
    community-score: uint,
    feedback-count: uint,
    total-stake: uint,
    last-updated: uint,
    age-bonus: uint
  }
)

(define-map user-feedback
  { name: (string-ascii 64), rater: principal }
  {
    rating: uint,
    category: (string-ascii 20),
    stake-amount: uint,
    submitted-at: uint
  }
)

(define-map technical-metrics
  { name: (string-ascii 64) }
  {
    resolution-success: uint,
    uptime-score: uint,
    renewal-consistency: uint,
    transfers-count: uint,
    last-activity: uint
  }
)

(define-map reputation-leaderboard
  { rank: uint }
  {
    name: (string-ascii 64),
    score: uint,
    category: (string-ascii 20)
  }
)

;; Authorization functions
(define-public (set-authorized-contract (contract principal))
  (begin
    (asserts! (is-none (var-get authorized-contract)) ERR_UNAUTHORIZED)
    (var-set authorized-contract (some contract))
    (ok true)
  )
)

;; Initialize reputation for new names
(define-public (initialize-reputation (name (string-ascii 64)))
  (begin
    (asserts! (is-eq (some contract-caller) (var-get authorized-contract)) ERR_UNAUTHORIZED)
    (asserts! (is-none (map-get? name-reputation { name: name })) ERR_ALREADY_RATED)
    
    (map-set name-reputation
      { name: name }
      {
        overall-score: INITIAL_REPUTATION,
        technical-score: INITIAL_REPUTATION,
        community-score: INITIAL_REPUTATION,
        feedback-count: u0,
        total-stake: u0,
        last-updated: stacks-block-height,
        age-bonus: u0
      }
    )
    
    (map-set technical-metrics
      { name: name }
      {
        resolution-success: u0,
        uptime-score: INITIAL_REPUTATION,
        renewal-consistency: u0,
        transfers-count: u0,
        last-activity: stacks-block-height
      }
    )
    
    (ok true)
  )
)

;; Submit community feedback (costs STX to prevent spam)
(define-public (submit-feedback (name (string-ascii 64)) (rating uint) (category (string-ascii 20)))
  (let (
    (existing-feedback (map-get? user-feedback { name: name, rater: tx-sender }))
    (stake-amount MIN_FEEDBACK_STAKE)
  )
    (asserts! (<= rating MAX_REPUTATION) ERR_INVALID_RATING)
    (asserts! (is-none existing-feedback) ERR_ALREADY_RATED)
    (asserts! (>= (stx-get-balance tx-sender) stake-amount) ERR_INSUFFICIENT_STAKE)
    
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    
    (map-set user-feedback
      { name: name, rater: tx-sender }
      {
        rating: rating,
        category: category,
        stake-amount: stake-amount,
        submitted-at: stacks-block-height
      }
    )
    
    (unwrap-panic (update-community-score name))
    (ok true)
  )
)

;; Update technical metrics (only by authorized contract)
(define-public (update-technical-metrics (name (string-ascii 64)) (resolution-success uint) (uptime-score uint))
  (begin
    (asserts! (is-eq (some contract-caller) (var-get authorized-contract)) ERR_UNAUTHORIZED)
    
    (let ((current-metrics (default-to 
      { resolution-success: u0, uptime-score: INITIAL_REPUTATION, renewal-consistency: u0, transfers-count: u0, last-activity: u0 }
      (map-get? technical-metrics { name: name }))))
      
      (map-set technical-metrics
        { name: name }
        (merge current-metrics {
          resolution-success: resolution-success,
          uptime-score: uptime-score,
          last-activity: stacks-block-height
        })
      )
      
      (unwrap-panic (update-technical-score name))
      (ok true)
    )
  )
)

;; Record name activity events
(define-public (record-activity (name (string-ascii 64)) (activity-type (string-ascii 20)))
  (begin
    (asserts! (is-eq (some contract-caller) (var-get authorized-contract)) ERR_UNAUTHORIZED)
    
    (let ((current-metrics (default-to 
      { resolution-success: u0, uptime-score: INITIAL_REPUTATION, renewal-consistency: u0, transfers-count: u0, last-activity: u0 }
      (map-get? technical-metrics { name: name }))))
      
      (map-set technical-metrics
        { name: name }
        (merge current-metrics {
          renewal-consistency: (if (is-eq activity-type "renewal") 
            (+ (get renewal-consistency current-metrics) u100) 
            (get renewal-consistency current-metrics)),
          transfers-count: (if (is-eq activity-type "transfer")
            (+ (get transfers-count current-metrics) u1)
            (get transfers-count current-metrics)),
          last-activity: stacks-block-height
        })
      )
      
      (ok true)
    )
  )
)

;; Private functions for score calculations
(define-private (update-community-score (name (string-ascii 64)))
  (let (
    (current-rep (default-to 
      { overall-score: INITIAL_REPUTATION, technical-score: INITIAL_REPUTATION, community-score: INITIAL_REPUTATION, 
        feedback-count: u0, total-stake: u0, last-updated: u0, age-bonus: u0 }
      (map-get? name-reputation { name: name })))
    (weighted-average (calculate-weighted-community-average name))
  )
    (map-set name-reputation
      { name: name }
      (merge current-rep {
        community-score: weighted-average,
        feedback-count: (+ (get feedback-count current-rep) u1),
        overall-score: (calculate-overall-score name)
      })
    )
    (ok true)
  )
)

(define-private (update-technical-score (name (string-ascii 64)))
  (let (
    (current-rep (default-to 
      { overall-score: INITIAL_REPUTATION, technical-score: INITIAL_REPUTATION, community-score: INITIAL_REPUTATION, 
        feedback-count: u0, total-stake: u0, last-updated: u0, age-bonus: u0 }
      (map-get? name-reputation { name: name })))
    (tech-score (calculate-technical-score name))
  )
    (map-set name-reputation
      { name: name }
      (merge current-rep {
        technical-score: tech-score,
        overall-score: (calculate-overall-score name),
        last-updated: stacks-block-height
      })
    )
    (ok true)
  )
)

(define-private (calculate-weighted-community-average (name (string-ascii 64)))
  ;; Simplified calculation - in practice would aggregate all feedback
  (let ((sample-feedback (map-get? user-feedback { name: name, rater: tx-sender })))
    (match sample-feedback
      feedback (get rating feedback)
      INITIAL_REPUTATION
    )
  )
)

(define-private (calculate-technical-score (name (string-ascii 64)))
  (let ((metrics (map-get? technical-metrics { name: name })))
    (match metrics
      m (let (
          (uptime-weight u4000) ;; 40%
          (resolution-weight u3000) ;; 30%  
          (consistency-weight u3000) ;; 30%
          (capped-consistency (if (> (get renewal-consistency m) MAX_REPUTATION) MAX_REPUTATION (get renewal-consistency m)))
        )
        (+ (+ (/ (* (get uptime-score m) uptime-weight) BPS)
              (/ (* (get resolution-success m) resolution-weight) BPS))
           (/ (* capped-consistency consistency-weight) BPS))
      )
      INITIAL_REPUTATION
    )
  )
)

(define-private (calculate-overall-score (name (string-ascii 64)))
  (let (
    (reputation (map-get? name-reputation { name: name }))
    (tech-weight u6000) ;; 60% technical
    (community-weight u4000) ;; 40% community
  )
    (match reputation
      rep (+ (/ (* (get technical-score rep) tech-weight) BPS)
             (/ (* (get community-score rep) community-weight) BPS))
      INITIAL_REPUTATION
    )
  )
)

;; Query functions
(define-read-only (get-name-reputation (name (string-ascii 64)))
  (map-get? name-reputation { name: name })
)

(define-read-only (get-technical-metrics (name (string-ascii 64)))
  (map-get? technical-metrics { name: name })
)

(define-read-only (get-user-feedback (name (string-ascii 64)) (rater principal))
  (map-get? user-feedback { name: name, rater: rater })
)

(define-read-only (get-reputation-score (name (string-ascii 64)))
  (match (map-get? name-reputation { name: name })
    reputation (get overall-score reputation)
    u0
  )
)

(define-read-only (is-high-reputation (name (string-ascii 64)))
  (>= (get-reputation-score name) u7500) ;; 75% threshold
)

(define-read-only (get-reputation-breakdown (name (string-ascii 64)))
  (match (map-get? name-reputation { name: name })
    reputation {
      overall: (get overall-score reputation),
      technical: (get technical-score reputation),
      community: (get community-score reputation),
      feedback-count: (get feedback-count reputation),
      age-bonus: (get age-bonus reputation)
    }
    { overall: u0, technical: u0, community: u0, feedback-count: u0, age-bonus: u0 }
  )
)

(define-read-only (get-authorized-contract)
  (var-get authorized-contract)
)
