;; Parts Replacement Contract
;; Manages component inventory and installation services

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u400))
(define-constant ERR_INVALID_PART (err u401))
(define-constant ERR_INSUFFICIENT_INVENTORY (err u402))
(define-constant ERR_INVALID_ORDER (err u403))
(define-constant ERR_ORDER_NOT_FOUND (err u404))
(define-constant ERR_PART_EXISTS (err u405))

;; Data Variables
(define-data-var total-parts uint u0)
(define-data-var total-orders uint u0)
(define-data-var parts-token-supply uint u0)

;; Data Maps
(define-map parts-inventory
  { part-id: uint }
  {
    name: (string-ascii 100),
    category: (string-ascii 50),
    manufacturer: (string-ascii 50),
    model: (string-ascii 50),
    quantity: uint,
    unit-price: uint,
    compatibility: (string-ascii 100),
    warranty-period: uint,
    active: bool
  }
)

(define-map parts-orders
  { order-id: uint }
  {
    customer: principal,
    part-id: uint,
    quantity: uint,
    total-cost: uint,
    order-date: uint,
    status: (string-ascii 20),
    technician: (optional principal),
    installation-date: (optional uint),
    completed: bool
  }
)

(define-map installation-records
  { installation-id: uint }
  {
    order-id: uint,
    system-id: uint,
    part-id: uint,
    technician: principal,
    installation-date: uint,
    warranty-start: uint,
    notes: (string-ascii 200),
    verified: bool
  }
)

(define-map user-parts-tokens
  { user: principal }
  { balance: uint }
)

(define-map authorized-suppliers
  { supplier: principal }
  {
    authorized: bool,
    rating: uint,
    specialization: (string-ascii 50)
  }
)

(define-map authorized-installers
  { installer: principal }
  {
    authorized: bool,
    certification: (string-ascii 50),
    rating: uint
  }
)

;; Private Functions
(define-private (is-authorized-supplier (user principal))
  (or
    (is-eq user CONTRACT_OWNER)
    (default-to false (get authorized (map-get? authorized-suppliers { supplier: user })))
  )
)

(define-private (is-authorized-installer (user principal))
  (or
    (is-eq user CONTRACT_OWNER)
    (default-to false (get authorized (map-get? authorized-installers { installer: user })))
  )
)

(define-private (mint-parts-tokens (recipient principal) (amount uint))
  (let ((current-balance (default-to u0 (get balance (map-get? user-parts-tokens { user: recipient })))))
    (map-set user-parts-tokens
      { user: recipient }
      { balance: (+ current-balance amount) }
    )
    (var-set parts-token-supply (+ (var-get parts-token-supply) amount))
    (ok amount)
  )
)

(define-private (calculate-order-cost (part-id uint) (quantity uint))
  (match (map-get? parts-inventory { part-id: part-id })
    part-info (* (get unit-price part-info) quantity)
    u0
  )
)

;; Public Functions
(define-public (add-part-to-inventory (part-id uint) (name (string-ascii 100)) (category (string-ascii 50))
                                     (manufacturer (string-ascii 50)) (model (string-ascii 50))
                                     (quantity uint) (unit-price uint) (compatibility (string-ascii 100))
                                     (warranty-period uint))
  (begin
    (asserts! (is-authorized-supplier tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-none (map-get? parts-inventory { part-id: part-id })) ERR_PART_EXISTS)
    (map-set parts-inventory
      { part-id: part-id }
      {
        name: name,
        category: category,
        manufacturer: manufacturer,
        model: model,
        quantity: quantity,
        unit-price: unit-price,
        compatibility: compatibility,
        warranty-period: warranty-period,
        active: true
      }
    )
    (var-set total-parts (+ (var-get total-parts) u1))
    (mint-parts-tokens tx-sender u20)
  )
)

(define-public (update-inventory (part-id uint) (new-quantity uint))
  (let ((part-info (map-get? parts-inventory { part-id: part-id })))
    (asserts! (is-authorized-supplier tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-some part-info) ERR_INVALID_PART)
    (map-set parts-inventory
      { part-id: part-id }
      (merge (unwrap-panic part-info) { quantity: new-quantity })
    )
    (mint-parts-tokens tx-sender u10)
  )
)

(define-public (place-parts-order (part-id uint) (quantity uint))
  (let ((part-info (map-get? parts-inventory { part-id: part-id }))
        (order-id (+ (var-get total-orders) u1)))
    (asserts! (is-some part-info) ERR_INVALID_PART)
    (asserts! (>= (get quantity (unwrap-panic part-info)) quantity) ERR_INSUFFICIENT_INVENTORY)

    (let ((total-cost (calculate-order-cost part-id quantity)))
      (map-set parts-orders
        { order-id: order-id }
        {
          customer: tx-sender,
          part-id: part-id,
          quantity: quantity,
          total-cost: total-cost,
          order-date: block-height,
          status: "pending",
          technician: none,
          installation-date: none,
          completed: false
        }
      )

      ;; Update inventory
      (map-set parts-inventory
        { part-id: part-id }
        (merge (unwrap-panic part-info) {
          quantity: (- (get quantity (unwrap-panic part-info)) quantity)
        })
      )

      (var-set total-orders order-id)
      (mint-parts-tokens tx-sender u15)
    )
  )
)

(define-public (assign-installer (order-id uint) (technician principal))
  (let ((order-info (map-get? parts-orders { order-id: order-id })))
    (asserts! (is-authorized-supplier tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-some order-info) ERR_ORDER_NOT_FOUND)
    (asserts! (is-authorized-installer technician) ERR_UNAUTHORIZED)

    (map-set parts-orders
      { order-id: order-id }
      (merge (unwrap-panic order-info) {
        technician: (some technician),
        status: "assigned"
      })
    )

    (ok true)
  )
)

(define-public (complete-installation (order-id uint) (system-id uint) (notes (string-ascii 200)))
  (let ((order-info (map-get? parts-orders { order-id: order-id }))
        (installation-id (+ order-id block-height)))
    (asserts! (is-some order-info) ERR_ORDER_NOT_FOUND)
    (asserts! (is-authorized-installer tx-sender) ERR_UNAUTHORIZED)

    (let ((order-data (unwrap-panic order-info)))
      ;; Update order status
      (map-set parts-orders
        { order-id: order-id }
        (merge order-data {
          status: "completed",
          installation-date: (some block-height),
          completed: true
        })
      )

      ;; Create installation record
      (map-set installation-records
        { installation-id: installation-id }
        {
          order-id: order-id,
          system-id: system-id,
          part-id: (get part-id order-data),
          technician: tx-sender,
          installation-date: block-height,
          warranty-start: block-height,
          notes: notes,
          verified: false
        }
      )

      (mint-parts-tokens tx-sender u50)
    )
  )
)

(define-public (verify-installation (installation-id uint))
  (let ((installation-info (map-get? installation-records { installation-id: installation-id })))
    (asserts! (is-authorized-supplier tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-some installation-info) ERR_ORDER_NOT_FOUND)

    (map-set installation-records
      { installation-id: installation-id }
      (merge (unwrap-panic installation-info) { verified: true })
    )

    (mint-parts-tokens tx-sender u25)
  )
)

(define-public (cancel-order (order-id uint))
  (let ((order-info (map-get? parts-orders { order-id: order-id })))
    (asserts! (is-some order-info) ERR_ORDER_NOT_FOUND)
    (asserts! (is-eq tx-sender (get customer (unwrap-panic order-info))) ERR_UNAUTHORIZED)

    (let ((order-data (unwrap-panic order-info)))
      ;; Restore inventory
      (let ((part-info (map-get? parts-inventory { part-id: (get part-id order-data) })))
        (map-set parts-inventory
          { part-id: (get part-id order-data) }
          (merge (unwrap-panic part-info) {
            quantity: (+ (get quantity (unwrap-panic part-info)) (get quantity order-data))
          })
        )
      )

      ;; Update order status
      (map-set parts-orders
        { order-id: order-id }
        (merge order-data { status: "cancelled" })
      )

      (ok true)
    )
  )
)

(define-public (authorize-supplier (supplier principal) (specialization (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set authorized-suppliers
      { supplier: supplier }
      {
        authorized: true,
        rating: u5,
        specialization: specialization
      }
    )
    (ok true)
  )
)

(define-public (authorize-installer (installer principal) (certification (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set authorized-installers
      { installer: installer }
      {
        authorized: true,
        certification: certification,
        rating: u5
      }
    )
    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-part-info (part-id uint))
  (map-get? parts-inventory { part-id: part-id })
)

(define-read-only (get-order-info (order-id uint))
  (map-get? parts-orders { order-id: order-id })
)

(define-read-only (get-installation-record (installation-id uint))
  (map-get? installation-records { installation-id: installation-id })
)

(define-read-only (get-user-tokens (user principal))
  (default-to u0 (get balance (map-get? user-parts-tokens { user: user })))
)

(define-read-only (get-total-parts)
  (var-get total-parts)
)

(define-read-only (get-total-orders)
  (var-get total-orders)
)

(define-read-only (get-token-supply)
  (var-get parts-token-supply)
)

(define-read-only (check-part-availability (part-id uint) (required-quantity uint))
  (match (map-get? parts-inventory { part-id: part-id })
    part-info (>= (get quantity part-info) required-quantity)
    false
  )
)
