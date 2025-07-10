;; Seasonal Maintenance Contract
;; Coordinates winterization and spring startup procedures

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_INVALID_SYSTEM (err u301))
(define-constant ERR_INVALID_SEASON (err u302))
(define-constant ERR_ALREADY_SCHEDULED (err u303))
(define-constant ERR_NOT_FOUND (err u304))
(define-constant SEASON_WINTER u1)
(define-constant SEASON_SPRING u2)
(define-constant SEASON_SUMMER u3)
(define-constant SEASON_FALL u4)

;; Data Variables
(define-data-var total-systems uint u0)
(define-data-var maintenance-token-supply uint u0)
(define-data-var current-season uint SEASON_SPRING)

;; Data Maps
(define-map sprinkler-systems
  { system-id: uint }
  {
    owner: principal,
    location: (string-ascii 100),
    system-type: (string-ascii 50),
    installation-date: uint,
    last-maintenance: uint,
    winterized: bool,
    active: bool
  }
)

(define-map maintenance-schedules
  { system-id: uint, season: uint }
  {
    scheduled-date: uint,
    maintenance-type: (string-ascii 50),
    technician: (optional principal),
    completed: bool,
    completion-date: (optional uint),
    notes: (string-ascii 200)
  }
)

(define-map seasonal-procedures
  { procedure-id: uint }
  {
    system-id: uint,
    season: uint,
    procedure-type: (string-ascii 50),
    steps-completed: uint,
    total-steps: uint,
    technician: principal,
    start-date: uint,
    completion-date: (optional uint)
  }
)

(define-map user-maintenance-tokens
  { user: principal }
  { balance: uint }
)

(define-map authorized-technicians
  { technician: principal }
  {
    authorized: bool,
    specialization: (string-ascii 50),
    rating: uint
  }
)

;; Private Functions
(define-private (is-authorized (user principal))
  (or
    (is-eq user CONTRACT_OWNER)
    (default-to false (get authorized (map-get? authorized-technicians { technician: user })))
  )
)

(define-private (is-valid-season (season uint))
  (and (>= season u1) (<= season u4))
)

(define-private (mint-maintenance-tokens (recipient principal) (amount uint))
  (let ((current-balance (default-to u0 (get balance (map-get? user-maintenance-tokens { user: recipient })))))
    (map-set user-maintenance-tokens
      { user: recipient }
      { balance: (+ current-balance amount) }
    )
    (var-set maintenance-token-supply (+ (var-get maintenance-token-supply) amount))
    (ok amount)
  )
)

(define-private (calculate-maintenance-reward (season uint) (system-complexity uint))
  (let ((base-reward u50)
        (seasonal-multiplier (if (or (is-eq season SEASON_WINTER) (is-eq season SEASON_SPRING)) u2 u1)))
    (* base-reward seasonal-multiplier system-complexity)
  )
)

;; Public Functions
(define-public (register-system (system-id uint) (location (string-ascii 100)) (system-type (string-ascii 50)))
  (begin
    (asserts! (is-none (map-get? sprinkler-systems { system-id: system-id })) ERR_ALREADY_SCHEDULED)
    (map-set sprinkler-systems
      { system-id: system-id }
      {
        owner: tx-sender,
        location: location,
        system-type: system-type,
        installation-date: block-height,
        last-maintenance: u0,
        winterized: false,
        active: true
      }
    )
    (var-set total-systems (+ (var-get total-systems) u1))
    (mint-maintenance-tokens tx-sender u25)
  )
)

(define-public (schedule-maintenance (system-id uint) (season uint) (scheduled-date uint) (maintenance-type (string-ascii 50)))
  (let ((system-info (map-get? sprinkler-systems { system-id: system-id })))
    (asserts! (is-some system-info) ERR_INVALID_SYSTEM)
    (asserts! (is-valid-season season) ERR_INVALID_SEASON)
    (asserts! (or (is-eq tx-sender (get owner (unwrap-panic system-info))) (is-authorized tx-sender)) ERR_UNAUTHORIZED)

    (map-set maintenance-schedules
      { system-id: system-id, season: season }
      {
        scheduled-date: scheduled-date,
        maintenance-type: maintenance-type,
        technician: none,
        completed: false,
        completion-date: none,
        notes: ""
      }
    )

    (mint-maintenance-tokens tx-sender u15)
  )
)

(define-public (assign-technician (system-id uint) (season uint) (technician principal))
  (let ((schedule-info (map-get? maintenance-schedules { system-id: system-id, season: season })))
    (asserts! (is-authorized tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-some schedule-info) ERR_NOT_FOUND)

    (map-set maintenance-schedules
      { system-id: system-id, season: season }
      (merge (unwrap-panic schedule-info) { technician: (some technician) })
    )

    (ok true)
  )
)

(define-public (start-winterization (system-id uint))
  (let ((system-info (map-get? sprinkler-systems { system-id: system-id }))
        (procedure-id (+ system-id block-height)))
    (asserts! (is-some system-info) ERR_INVALID_SYSTEM)
    (asserts! (is-authorized tx-sender) ERR_UNAUTHORIZED)

    (map-set seasonal-procedures
      { procedure-id: procedure-id }
      {
        system-id: system-id,
        season: SEASON_WINTER,
        procedure-type: "winterization",
        steps-completed: u0,
        total-steps: u8,
        technician: tx-sender,
        start-date: block-height,
        completion-date: none
      }
    )

    (mint-maintenance-tokens tx-sender u30)
  )
)

(define-public (complete-winterization (system-id uint) (procedure-id uint))
  (let ((system-info (map-get? sprinkler-systems { system-id: system-id }))
        (procedure-info (map-get? seasonal-procedures { procedure-id: procedure-id })))
    (asserts! (is-some system-info) ERR_INVALID_SYSTEM)
    (asserts! (is-some procedure-info) ERR_NOT_FOUND)
    (asserts! (is-authorized tx-sender) ERR_UNAUTHORIZED)

    ;; Update system as winterized
    (map-set sprinkler-systems
      { system-id: system-id }
      (merge (unwrap-panic system-info) {
        winterized: true,
        last-maintenance: block-height,
        active: false
      })
    )

    ;; Complete procedure
    (map-set seasonal-procedures
      { procedure-id: procedure-id }
      (merge (unwrap-panic procedure-info) {
        steps-completed: u8,
        completion-date: (some block-height)
      })
    )

    (mint-maintenance-tokens tx-sender u100)
  )
)

(define-public (start-spring-startup (system-id uint))
  (let ((system-info (map-get? sprinkler-systems { system-id: system-id }))
        (procedure-id (+ system-id block-height)))
    (asserts! (is-some system-info) ERR_INVALID_SYSTEM)
    (asserts! (is-authorized tx-sender) ERR_UNAUTHORIZED)

    (map-set seasonal-procedures
      { procedure-id: procedure-id }
      {
        system-id: system-id,
        season: SEASON_SPRING,
        procedure-type: "spring-startup",
        steps-completed: u0,
        total-steps: u6,
        technician: tx-sender,
        start-date: block-height,
        completion-date: none
      }
    )

    (mint-maintenance-tokens tx-sender u25)
  )
)

(define-public (complete-spring-startup (system-id uint) (procedure-id uint))
  (let ((system-info (map-get? sprinkler-systems { system-id: system-id }))
        (procedure-info (map-get? seasonal-procedures { procedure-id: procedure-id })))
    (asserts! (is-some system-info) ERR_INVALID_SYSTEM)
    (asserts! (is-some procedure-info) ERR_NOT_FOUND)
    (asserts! (is-authorized tx-sender) ERR_UNAUTHORIZED)

    ;; Update system as active
    (map-set sprinkler-systems
      { system-id: system-id }
      (merge (unwrap-panic system-info) {
        winterized: false,
        last-maintenance: block-height,
        active: true
      })
    )

    ;; Complete procedure
    (map-set seasonal-procedures
      { procedure-id: procedure-id }
      (merge (unwrap-panic procedure-info) {
        steps-completed: u6,
        completion-date: (some block-height)
      })
    )

    (mint-maintenance-tokens tx-sender u80)
  )
)

(define-public (update-season (new-season uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-valid-season new-season) ERR_INVALID_SEASON)
    (var-set current-season new-season)
    (ok new-season)
  )
)

(define-public (authorize-technician (technician principal) (specialization (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set authorized-technicians
      { technician: technician }
      {
        authorized: true,
        specialization: specialization,
        rating: u5
      }
    )
    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-system-info (system-id uint))
  (map-get? sprinkler-systems { system-id: system-id })
)

(define-read-only (get-maintenance-schedule (system-id uint) (season uint))
  (map-get? maintenance-schedules { system-id: system-id, season: season })
)

(define-read-only (get-procedure-info (procedure-id uint))
  (map-get? seasonal-procedures { procedure-id: procedure-id })
)

(define-read-only (get-user-tokens (user principal))
  (default-to u0 (get balance (map-get? user-maintenance-tokens { user: user })))
)

(define-read-only (get-current-season)
  (var-get current-season)
)

(define-read-only (get-total-systems)
  (var-get total-systems)
)

(define-read-only (get-token-supply)
  (var-get maintenance-token-supply)
)

(define-read-only (is-system-winterized (system-id uint))
  (match (map-get? sprinkler-systems { system-id: system-id })
    system-data (get winterized system-data)
    false
  )
)
