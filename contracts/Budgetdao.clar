(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u101))
(define-constant ERR_PROPOSAL_EXPIRED (err u102))
(define-constant ERR_ALREADY_VOTED (err u103))
(define-constant ERR_INSUFFICIENT_FUNDS (err u104))
(define-constant ERR_PROPOSAL_NOT_PASSED (err u105))
(define-constant ERR_ALREADY_EXECUTED (err u106))
(define-constant ERR_INVALID_AMOUNT (err u107))
(define-constant ERR_INVALID_DURATION (err u108))
(define-constant ERR_MILESTONE_NOT_FOUND (err u109))
(define-constant ERR_MILESTONE_ALREADY_COMPLETED (err u110))
(define-constant ERR_PREVIOUS_MILESTONE_INCOMPLETE (err u111))
(define-constant ERR_TIMELOCK_ACTIVE (err u112))
(define-constant ERR_INVALID_MILESTONE_COUNT (err u113))
(define-constant ERR_MILESTONE_VERIFICATION_REQUIRED (err u114))
(define-constant ERR_INSUFFICIENT_MILESTONE_VOTES (err u115))

(define-data-var proposal-counter uint u0)
(define-data-var milestone-allocation-counter uint u0)
(define-data-var total-budget uint u0)
(define-data-var min-votes-required uint u3)

(define-map proposals
  uint
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    amount: uint,
    recipient: principal,
    proposer: principal,
    votes-for: uint,
    votes-against: uint,
    end-block: uint,
    executed: bool,
    created-at: uint
  }
)

(define-map votes
  { proposal-id: uint, voter: principal }
  { vote: bool, stacks-block-height: uint }
)

(define-map member-status
  principal
  { is-member: bool, joined-at: uint }
)

(define-map milestone-allocations
  uint
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    total-amount: uint,
    recipient: principal,
    creator: principal,
    milestone-count: uint,
    created-at: uint,
    timelock-blocks: uint,
    requires-verification: bool
  }
)

(define-map milestones
  { allocation-id: uint, milestone-index: uint }
  {
    description: (string-ascii 300),
    amount: uint,
    completed: bool,
    completion-block: uint,
    timelock-end: uint,
    verification-votes: uint,
    verification-required: uint
  }
)

(define-map milestone-verifications
  { allocation-id: uint, milestone-index: uint, verifier: principal }
  { verified: bool, verification-block: uint }
)

(define-public (initialize-budget (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (var-set total-budget amount)
    (ok true)
  )
)

(define-public (add-member (member principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (map-set member-status member { is-member: true, joined-at: stacks-block-height })
    (ok true)
  )
)

(define-public (remove-member (member principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (map-set member-status member { is-member: false, joined-at: u0 })
    (ok true)
  )
)

(define-public (create-proposal 
  (title (string-ascii 100))
  (description (string-ascii 500))
  (amount uint)
  (recipient principal)
  (duration uint)
)
  (let
    (
      (proposal-id (+ (var-get proposal-counter) u1))
      (end-block (+ stacks-block-height duration))
    )
    (asserts! (is-member tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (<= amount (var-get total-budget)) ERR_INSUFFICIENT_FUNDS)
    (asserts! (> duration u0) ERR_INVALID_DURATION)
    
    (map-set proposals proposal-id
      {
        title: title,
        description: description,
        amount: amount,
        recipient: recipient,
        proposer: tx-sender,
        votes-for: u0,
        votes-against: u0,
        end-block: end-block,
        executed: false,
        created-at: stacks-block-height
      }
    )
    (var-set proposal-counter proposal-id)
    (ok proposal-id)
  )
)

(define-public (vote-on-proposal (proposal-id uint) (vote-for bool))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
      (existing-vote (map-get? votes { proposal-id: proposal-id, voter: tx-sender }))
    )
    (asserts! (is-member tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (<= stacks-block-height (get end-block proposal)) ERR_PROPOSAL_EXPIRED)
    (asserts! (is-none existing-vote) ERR_ALREADY_VOTED)
    
    (map-set votes 
      { proposal-id: proposal-id, voter: tx-sender }
      { vote: vote-for, stacks-block-height: stacks-block-height }
    )
    
    (if vote-for
      (map-set proposals proposal-id
        (merge proposal { votes-for: (+ (get votes-for proposal) u1) })
      )
      (map-set proposals proposal-id
        (merge proposal { votes-against: (+ (get votes-against proposal) u1) })
      )
    )
    (ok true)
  )
)

(define-public (execute-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
    )
    (asserts! (> stacks-block-height (get end-block proposal)) ERR_PROPOSAL_EXPIRED)
    (asserts! (not (get executed proposal)) ERR_ALREADY_EXECUTED)
    (asserts! (>= (get votes-for proposal) (var-get min-votes-required)) ERR_PROPOSAL_NOT_PASSED)
    (asserts! (> (get votes-for proposal) (get votes-against proposal)) ERR_PROPOSAL_NOT_PASSED)
    (asserts! (>= (var-get total-budget) (get amount proposal)) ERR_INSUFFICIENT_FUNDS)
    
    (try! (stx-transfer? (get amount proposal) (as-contract tx-sender) (get recipient proposal)))
    
    (var-set total-budget (- (var-get total-budget) (get amount proposal)))
    (map-set proposals proposal-id (merge proposal { executed: true }))
    (ok true)
  )
)

(define-public (fund-contract)
  (let
    (
      (amount (stx-get-balance tx-sender))
    )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set total-budget (+ (var-get total-budget) amount))
    (ok amount)
  )
)

(define-public (set-min-votes (new-min uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (> new-min u0) ERR_INVALID_AMOUNT)
    (var-set min-votes-required new-min)
    (ok true)
  )
)

(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id)
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (is-member (user principal))
  (default-to false (get is-member (map-get? member-status user)))
)

(define-read-only (get-total-budget)
  (var-get total-budget)
)

(define-read-only (get-proposal-count)
  (var-get proposal-counter)
)

(define-read-only (get-min-votes-required)
  (var-get min-votes-required)
)

(define-read-only (is-proposal-active (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (<= stacks-block-height (get end-block proposal))
    false
  )
)

(define-read-only (get-proposal-status (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal 
    {
      active: (<= stacks-block-height (get end-block proposal)),
      passed: (and 
        (>= (get votes-for proposal) (var-get min-votes-required))
        (> (get votes-for proposal) (get votes-against proposal))
      ),
      executed: (get executed proposal)
    }
    { active: false, passed: false, executed: false }
  )
)

(define-public (create-milestone-allocation
  (title (string-ascii 100))
  (description (string-ascii 500))
  (total-amount uint)
  (recipient principal)
  (milestone-descriptions (list 10 (string-ascii 300)))
  (milestone-amounts (list 10 uint))
  (timelock-blocks uint)
  (requires-verification bool)
)
  (let
    (
      (allocation-id (+ (var-get milestone-allocation-counter) u1))
      (milestone-count (len milestone-descriptions))
      (total-milestone-amount (fold + milestone-amounts u0))
    )
    (asserts! (is-member tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (> total-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (<= total-amount (var-get total-budget)) ERR_INSUFFICIENT_FUNDS)
    (asserts! (and (> milestone-count u0) (<= milestone-count u10)) ERR_INVALID_MILESTONE_COUNT)
    (asserts! (is-eq total-amount total-milestone-amount) ERR_INVALID_AMOUNT)
    (asserts! (> timelock-blocks u0) ERR_INVALID_DURATION)
    
    (map-set milestone-allocations allocation-id
      {
        title: title,
        description: description,
        total-amount: total-amount,
        recipient: recipient,
        creator: tx-sender,
        milestone-count: milestone-count,
        created-at: stacks-block-height,
        timelock-blocks: timelock-blocks,
        requires-verification: requires-verification
      }
    )
    
    (try! (create-initial-milestones allocation-id milestone-descriptions milestone-amounts requires-verification))
    (var-set milestone-allocation-counter allocation-id)
    (var-set total-budget (- (var-get total-budget) total-amount))
    (ok allocation-id)
  )
)

(define-private (create-initial-milestones
  (allocation-id uint)
  (descriptions (list 10 (string-ascii 300)))
  (amounts (list 10 uint))
  (requires-verification bool)
)
  (let
    (
      (verification-required (if requires-verification (var-get min-votes-required) u0))
    )
    (asserts! (is-eq (len descriptions) (len amounts)) ERR_INVALID_MILESTONE_COUNT)
    (fold create-milestone-entry 
      (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9)
      {
        allocation-id: allocation-id,
        descriptions: descriptions,
        amounts: amounts,
        verification-required: verification-required,
        max-index: (len descriptions)
      }
    )
    (ok true)
  )
)

(define-private (create-milestone-entry
  (index uint)
  (data {
    allocation-id: uint,
    descriptions: (list 10 (string-ascii 300)),
    amounts: (list 10 uint),
    verification-required: uint,
    max-index: uint
  })
)
  (if (< index (get max-index data))
    (begin
      (map-set milestones
        { allocation-id: (get allocation-id data), milestone-index: index }
        {
          description: (unwrap-panic (element-at (get descriptions data) index)),
          amount: (unwrap-panic (element-at (get amounts data) index)),
          completed: false,
          completion-block: u0,
          timelock-end: u0,
          verification-votes: u0,
          verification-required: (get verification-required data)
        }
      )
      data
    )
    data
  )
)

(define-public (complete-milestone (allocation-id uint) (milestone-index uint))
  (let
    (
      (allocation (unwrap! (map-get? milestone-allocations allocation-id) ERR_MILESTONE_NOT_FOUND))
      (milestone (unwrap! (map-get? milestones { allocation-id: allocation-id, milestone-index: milestone-index }) ERR_MILESTONE_NOT_FOUND))
      (timelock-end (+ stacks-block-height (get timelock-blocks allocation)))
    )
    (asserts! (is-eq tx-sender (get recipient allocation)) ERR_NOT_AUTHORIZED)
    (asserts! (not (get completed milestone)) ERR_MILESTONE_ALREADY_COMPLETED)
    (asserts! (or (is-eq milestone-index u0) (is-previous-milestone-complete allocation-id milestone-index)) ERR_PREVIOUS_MILESTONE_INCOMPLETE)
    
    (map-set milestones
      { allocation-id: allocation-id, milestone-index: milestone-index }
      (merge milestone
        {
          completed: true,
          completion-block: stacks-block-height,
          timelock-end: timelock-end
        }
      )
    )
    (ok true)
  )
)

(define-public (verify-milestone (allocation-id uint) (milestone-index uint))
  (let
    (
      (allocation (unwrap! (map-get? milestone-allocations allocation-id) ERR_MILESTONE_NOT_FOUND))
      (milestone (unwrap! (map-get? milestones { allocation-id: allocation-id, milestone-index: milestone-index }) ERR_MILESTONE_NOT_FOUND))
      (existing-verification (map-get? milestone-verifications { allocation-id: allocation-id, milestone-index: milestone-index, verifier: tx-sender }))
    )
    (asserts! (is-member tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (get completed milestone) ERR_MILESTONE_VERIFICATION_REQUIRED)
    (asserts! (get requires-verification allocation) ERR_MILESTONE_VERIFICATION_REQUIRED)
    (asserts! (is-none existing-verification) ERR_ALREADY_VOTED)
    
    (map-set milestone-verifications
      { allocation-id: allocation-id, milestone-index: milestone-index, verifier: tx-sender }
      { verified: true, verification-block: stacks-block-height }
    )
    
    (map-set milestones
      { allocation-id: allocation-id, milestone-index: milestone-index }
      (merge milestone { verification-votes: (+ (get verification-votes milestone) u1) })
    )
    (ok true)
  )
)

(define-public (claim-milestone-funds (allocation-id uint) (milestone-index uint))
  (let
    (
      (allocation (unwrap! (map-get? milestone-allocations allocation-id) ERR_MILESTONE_NOT_FOUND))
      (milestone (unwrap! (map-get? milestones { allocation-id: allocation-id, milestone-index: milestone-index }) ERR_MILESTONE_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get recipient allocation)) ERR_NOT_AUTHORIZED)
    (asserts! (get completed milestone) ERR_MILESTONE_VERIFICATION_REQUIRED)
    (asserts! (> stacks-block-height (get timelock-end milestone)) ERR_TIMELOCK_ACTIVE)
    
    (if (get requires-verification allocation)
      (asserts! (>= (get verification-votes milestone) (get verification-required milestone)) ERR_INSUFFICIENT_MILESTONE_VOTES)
      true
    )
    
    (try! (stx-transfer? (get amount milestone) (as-contract tx-sender) (get recipient allocation)))
    (ok (get amount milestone))
  )
)

(define-private (is-previous-milestone-complete (allocation-id uint) (milestone-index uint))
  (if (is-eq milestone-index u0)
    true
    (match (map-get? milestones { allocation-id: allocation-id, milestone-index: (- milestone-index u1) })
      prev-milestone (get completed prev-milestone)
      false
    )
  )
)

(define-read-only (get-milestone-allocation (allocation-id uint))
  (map-get? milestone-allocations allocation-id)
)

(define-read-only (get-milestone (allocation-id uint) (milestone-index uint))
  (map-get? milestones { allocation-id: allocation-id, milestone-index: milestone-index })
)

(define-read-only (get-milestone-verification (allocation-id uint) (milestone-index uint) (verifier principal))
  (map-get? milestone-verifications { allocation-id: allocation-id, milestone-index: milestone-index, verifier: verifier })
)

(define-read-only (get-milestone-allocation-count)
  (var-get milestone-allocation-counter)
)

(define-read-only (is-milestone-claimable (allocation-id uint) (milestone-index uint))
  (match (get-milestone allocation-id milestone-index)
    milestone
    (match (get-milestone-allocation allocation-id)
      allocation
      (and
        (get completed milestone)
        (> stacks-block-height (get timelock-end milestone))
        (or
          (not (get requires-verification allocation))
          (>= (get verification-votes milestone) (get verification-required milestone))
        )
      )
      false
    )
    false
  )
)