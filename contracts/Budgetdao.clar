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

(define-data-var proposal-counter uint u0)
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