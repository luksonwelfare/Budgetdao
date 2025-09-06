;; Budget Allocation Analytics
;; Tracks spending patterns and provides governance insights for better DAO management

(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_PERIOD (err u200))
(define-constant ERR_ANALYTICS_NOT_FOUND (err u201))
(define-constant ERR_INVALID_CATEGORY (err u202))

;; Analytics period constants (in blocks)
(define-constant PERIOD_DAILY u144)      ;; ~1 day
(define-constant PERIOD_WEEKLY u1008)    ;; ~7 days
(define-constant PERIOD_MONTHLY u4320)   ;; ~30 days
(define-constant PERIOD_QUARTERLY u12960) ;; ~90 days

(define-data-var analytics-counter uint u0)
(define-data-var last-analytics-update uint u0)

;; Track spending by category
(define-map spending-categories
  (string-ascii 32)
  {
    total-allocated: uint,
    total-spent: uint,
    proposal-count: uint,
    success-rate: uint,
    avg-amount: uint,
    last-updated: uint
  }
)

;; Periodic budget analytics
(define-map budget-analytics
  { period-start: uint, period-type: uint }
  {
    total-proposals-created: uint,
    total-proposals-passed: uint,
    total-budget-allocated: uint,
    total-budget-spent: uint,
    avg-proposal-amount: uint,
    participation-rate: uint,
    top-category: (string-ascii 32),
    created-at: uint
  }
)

;; Member participation metrics
(define-map member-analytics
  { member: principal, period-start: uint }
  {
    proposals-created: uint,
    votes-cast: uint,
    delegation-power: uint,
    participation-score: uint,
    last-activity: uint
  }
)

;; Proposal category mapping
(define-map proposal-categories
  uint
  {
    category: (string-ascii 32),
    amount: uint,
    passed: bool,
    execution-time: uint
  }
)

;; Track budget utilization over time
(define-map budget-utilization
  uint
  {
    period-start: uint,
    period-end: uint,
    starting-budget: uint,
    ending-budget: uint,
    utilization-rate: uint,
    efficiency-score: uint
  }
)

;; Record proposal category for analytics
(define-public (categorize-proposal (proposal-id uint) (category (string-ascii 32)))
  (let
    (
      (proposal (unwrap! (contract-call? .Budgetdao get-proposal proposal-id) ERR_ANALYTICS_NOT_FOUND))
    )
    (asserts! (contract-call? .Budgetdao is-member tx-sender) ERR_UNAUTHORIZED)
    (asserts! (> (len category) u0) ERR_INVALID_CATEGORY)
    
    (map-set proposal-categories
      proposal-id
      {
        category: category,
        amount: (get amount proposal),
        passed: false,
        execution-time: u0
      }
    )
    (ok true)
  )
)

;; Update proposal analytics when executed
(define-public (update-proposal-execution (proposal-id uint))
  (let
    (
      (proposal (unwrap! (contract-call? .Budgetdao get-proposal proposal-id) ERR_ANALYTICS_NOT_FOUND))
      (category-data (map-get? proposal-categories proposal-id))
    )
    (asserts! (contract-call? .Budgetdao is-member tx-sender) ERR_UNAUTHORIZED)
    (asserts! (get executed proposal) ERR_UNAUTHORIZED)
    
    (match category-data
      cat-data
        (begin
          ;; Update proposal category record
          (map-set proposal-categories
            proposal-id
            (merge cat-data {
              passed: true,
              execution-time: stacks-block-height
            })
          )
          
          ;; Update category spending analytics
          (update-category-analytics (get category cat-data) (get amount cat-data) true)
        )
      ;; If no category set, use default
      (update-category-analytics "general" (get amount proposal) true)
    )
    (ok true)
  )
)

;; Generate periodic analytics
(define-public (generate-period-analytics (period-type uint))
  (let
    (
      (current-block stacks-block-height)
      (period-length (get-period-length period-type))
      (period-start (- current-block (mod current-block period-length)))
    )
    (asserts! (is-valid-period-type period-type) ERR_INVALID_PERIOD)
    
    (let
      (
        (analytics-id (+ (var-get analytics-counter) u1))
        (proposal-count (contract-call? .Budgetdao get-proposal-count))
        (total-budget (contract-call? .Budgetdao get-total-budget))
      )
      (map-set budget-analytics
        { period-start: period-start, period-type: period-type }
        {
          total-proposals-created: proposal-count,
          total-proposals-passed: (calculate-passed-proposals),
          total-budget-allocated: total-budget,
          total-budget-spent: (calculate-spent-budget),
          avg-proposal-amount: (calculate-avg-proposal-amount),
          participation-rate: (calculate-participation-rate),
          top-category: (get-top-spending-category),
          created-at: current-block
        }
      )
      
      (var-set analytics-counter analytics-id)
      (var-set last-analytics-update current-block)
      (ok analytics-id)
    )
  )
)

;; Update member participation metrics
(define-public (update-member-participation (member principal))
  (let
    (
      (current-block stacks-block-height)
      (period-start (- current-block PERIOD_WEEKLY))
      (current-metrics (default-to
        { proposals-created: u0, votes-cast: u0, delegation-power: u0, participation-score: u0, last-activity: u0 }
        (map-get? member-analytics { member: member, period-start: period-start })
      ))
      (delegation-power (default-to u0 (get delegator-count (contract-call? .Budgetdao get-delegation-power member))))
    )
    (asserts! (contract-call? .Budgetdao is-member member) ERR_UNAUTHORIZED)
    
    (map-set member-analytics
      { member: member, period-start: period-start }
      (merge current-metrics {
        delegation-power: delegation-power,
        participation-score: (calculate-member-score member),
        last-activity: current-block
      })
    )
    (ok true)
  )
)

;; Calculate budget utilization efficiency
(define-public (analyze-budget-utilization)
  (let
    (
      (current-budget (contract-call? .Budgetdao get-total-budget))
      (utilization-id (+ (var-get analytics-counter) u1))
      (period-start (- stacks-block-height PERIOD_MONTHLY))
    )
    (map-set budget-utilization
      utilization-id
      {
        period-start: period-start,
        period-end: stacks-block-height,
        starting-budget: current-budget,
        ending-budget: current-budget,
        utilization-rate: (calculate-utilization-rate),
        efficiency-score: (calculate-efficiency-score)
      }
    )
    (ok utilization-id)
  )
)

;; Helper functions
(define-private (update-category-analytics (category (string-ascii 32)) (amount uint) (passed bool))
  (let
    (
      (current-data (default-to
        { total-allocated: u0, total-spent: u0, proposal-count: u0, success-rate: u0, avg-amount: u0, last-updated: u0 }
        (map-get? spending-categories category)
      ))
      (new-count (+ (get proposal-count current-data) u1))
      (new-allocated (+ (get total-allocated current-data) amount))
      (new-spent (if passed (+ (get total-spent current-data) amount) (get total-spent current-data)))
    )
    (map-set spending-categories
      category
      {
        total-allocated: new-allocated,
        total-spent: new-spent,
        proposal-count: new-count,
        success-rate: (if (> new-count u0) (/ (* new-spent u100) new-allocated) u0),
        avg-amount: (/ new-allocated new-count),
        last-updated: stacks-block-height
      }
    )
  )
)

(define-private (get-period-length (period-type uint))
  (if (is-eq period-type u0) PERIOD_DAILY
    (if (is-eq period-type u1) PERIOD_WEEKLY
      (if (is-eq period-type u2) PERIOD_MONTHLY
        PERIOD_QUARTERLY)))
)

(define-private (is-valid-period-type (period-type uint))
  (<= period-type u3)
)

(define-private (calculate-passed-proposals)
  ;; Simplified calculation - in a real implementation, this would iterate through proposals
  (/ (contract-call? .Budgetdao get-proposal-count) u2)
)

(define-private (calculate-spent-budget)
  ;; Simplified calculation - would sum up all executed proposal amounts
  u500000
)

(define-private (calculate-avg-proposal-amount)
  (let
    (
      (proposal-count (contract-call? .Budgetdao get-proposal-count))
    )
    (if (> proposal-count u0)
      (/ (calculate-spent-budget) proposal-count)
      u0)
  )
)

(define-private (calculate-participation-rate)
  ;; Simplified - would calculate actual member participation
  u75
)

(define-private (get-top-spending-category)
  ;; Would iterate through categories to find highest spending
  "infrastructure"
)

(define-private (calculate-member-score (member principal))
  ;; Basic scoring algorithm based on activity
  (let
    (
      (is-member (contract-call? .Budgetdao is-member member))
    )
    (if is-member u80 u0)
  )
)

(define-private (calculate-utilization-rate)
  ;; Simplified utilization calculation
  u65
)

(define-private (calculate-efficiency-score)
  ;; Simplified efficiency scoring
  u70
)

;; Read-only functions
(define-read-only (get-category-analytics (category (string-ascii 32)))
  (map-get? spending-categories category)
)

(define-read-only (get-period-analytics (period-start uint) (period-type uint))
  (map-get? budget-analytics { period-start: period-start, period-type: period-type })
)

(define-read-only (get-member-participation (member principal) (period-start uint))
  (map-get? member-analytics { member: member, period-start: period-start })
)

(define-read-only (get-proposal-category (proposal-id uint))
  (map-get? proposal-categories proposal-id)
)

(define-read-only (get-budget-utilization (utilization-id uint))
  (map-get? budget-utilization utilization-id)
)

(define-read-only (get-analytics-summary)
  (ok {
    total-analytics-generated: (var-get analytics-counter),
    last-update: (var-get last-analytics-update),
    current-block: stacks-block-height
  })
)

(define-read-only (get-governance-health-score)
  (let
    (
      (participation-rate (calculate-participation-rate))
      (utilization-rate (calculate-utilization-rate))
      (efficiency-score (calculate-efficiency-score))
    )
    (ok {
      overall-score: (/ (+ participation-rate utilization-rate efficiency-score) u3),
      participation-rate: participation-rate,
      utilization-rate: utilization-rate,
      efficiency-score: efficiency-score,
      calculated-at: stacks-block-height
    })
  )
)

(define-read-only (predict-budget-runway)
  (let
    (
      (current-budget (contract-call? .Budgetdao get-total-budget))
      (avg-spending (calculate-avg-proposal-amount))
    )
    (ok {
      current-budget: current-budget,
      avg-monthly-spending: avg-spending,
      estimated-runway-months: (if (> avg-spending u0) (/ current-budget avg-spending) u0),
      calculated-at: stacks-block-height
    })
  )
)

(define-read-only (get-spending-trends)
  (ok {
    top-category: (get-top-spending-category),
    avg-proposal-size: (calculate-avg-proposal-amount),
    success-rate: (/ (calculate-passed-proposals) (contract-call? .Budgetdao get-proposal-count)),
    trend-period: PERIOD_MONTHLY,
    analyzed-at: stacks-block-height
  })
)
