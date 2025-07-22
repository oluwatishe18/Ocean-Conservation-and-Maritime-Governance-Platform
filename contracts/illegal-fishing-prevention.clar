;; Illegal Fishing Prevention Contract
;; Monitors fishing vessels and prevents overfishing in protected waters

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-VESSEL-NOT-FOUND (err u101))
(define-constant ERR-INVALID-QUOTA (err u102))
(define-constant ERR-QUOTA-EXCEEDED (err u103))
(define-constant ERR-FISHING-PROHIBITED (err u104))
(define-constant ERR-INVALID-COORDINATES (err u105))
(define-constant ERR-PERMIT-NOT-FOUND (err u106))
(define-constant ERR-ZONE-NOT-FOUND (err u107))

;; Data Variables
(define-data-var total-vessels uint u0)
(define-data-var total-violations uint u0)
(define-data-var total-zones uint u0)

;; Data Maps
(define-map vessels
  { vessel-id: uint }
  {
    owner: principal,
    name: (string-ascii 50),
    license-expiry: uint,
    quota-limit: uint,
    quota-used: uint,
    active: bool
  }
)

(define-map fishing-zones
  { zone-id: uint }
  {
    name: (string-ascii 50),
    lat-min: int,
    lat-max: int,
    lon-min: int,
    lon-max: int,
    fishing-allowed: bool,
    seasonal-restriction: bool
  }
)

(define-map violations
  { violation-id: uint }
  {
    vessel-id: uint,
    zone-id: uint,
    violation-type: (string-ascii 30),
    penalty-amount: uint,
    timestamp: uint,
    resolved: bool
  }
)

(define-map fishing-activities
  { activity-id: uint }
  {
    vessel-id: uint,
    zone-id: uint,
    catch-amount: uint,
    timestamp: uint,
    verified: bool
  }
)

;; Private Functions
(define-private (is-authorized (caller principal))
  (is-eq caller CONTRACT-OWNER)
)

(define-private (is-vessel-owner (vessel-id uint) (caller principal))
  (match (map-get? vessels { vessel-id: vessel-id })
    vessel-data (is-eq (get owner vessel-data) caller)
    false
  )
)

(define-private (is-in-zone (lat int) (lon int) (zone-id uint))
  (match (map-get? fishing-zones { zone-id: zone-id })
    zone-data (and
      (>= lat (get lat-min zone-data))
      (<= lat (get lat-max zone-data))
      (>= lon (get lon-min zone-data))
      (<= lon (get lon-max zone-data))
    )
    false
  )
)

;; Public Functions

;; Register a new fishing vessel
(define-public (register-vessel (name (string-ascii 50)) (quota-limit uint))
  (let ((vessel-id (+ (var-get total-vessels) u1)))
    (asserts! (> quota-limit u0) ERR-INVALID-QUOTA)
    (map-set vessels
      { vessel-id: vessel-id }
      {
        owner: tx-sender,
        name: name,
        license-expiry: (+ block-height u52560), ;; ~1 year
        quota-limit: quota-limit,
        quota-used: u0,
        active: true
      }
    )
    (var-set total-vessels vessel-id)
    (ok vessel-id)
  )
)

;; Create a fishing zone
(define-public (create-fishing-zone
  (name (string-ascii 50))
  (lat-min int) (lat-max int)
  (lon-min int) (lon-max int)
  (fishing-allowed bool))
  (begin
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (< lat-min lat-max) ERR-INVALID-COORDINATES)
    (asserts! (< lon-min lon-max) ERR-INVALID-COORDINATES)
    (let ((zone-id (+ (var-get total-zones) u1)))
      (map-set fishing-zones
        { zone-id: zone-id }
        {
          name: name,
          lat-min: lat-min,
          lat-max: lat-max,
          lon-min: lon-min,
          lon-max: lon-max,
          fishing-allowed: fishing-allowed,
          seasonal-restriction: false
        }
      )
      (var-set total-zones zone-id)
      (ok zone-id)
    )
  )
)

;; Report fishing activity
(define-public (report-fishing-activity
  (vessel-id uint)
  (zone-id uint)
  (lat int) (lon int)
  (catch-amount uint))
  (let (
    (vessel-data (unwrap! (map-get? vessels { vessel-id: vessel-id }) ERR-VESSEL-NOT-FOUND))
    (zone-data (unwrap! (map-get? fishing-zones { zone-id: zone-id }) ERR-ZONE-NOT-FOUND))
    (activity-id (+ (var-get total-vessels) u1))
  )
    (asserts! (is-vessel-owner vessel-id tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (get active vessel-data) ERR-VESSEL-NOT-FOUND)
    (asserts! (is-in-zone lat lon zone-id) ERR-INVALID-COORDINATES)
    (asserts! (get fishing-allowed zone-data) ERR-FISHING-PROHIBITED)
    (asserts! (<= (+ (get quota-used vessel-data) catch-amount) (get quota-limit vessel-data)) ERR-QUOTA-EXCEEDED)

    ;; Update vessel quota
    (map-set vessels
      { vessel-id: vessel-id }
      (merge vessel-data { quota-used: (+ (get quota-used vessel-data) catch-amount) })
    )

    ;; Record activity
    (map-set fishing-activities
      { activity-id: activity-id }
      {
        vessel-id: vessel-id,
        zone-id: zone-id,
        catch-amount: catch-amount,
        timestamp: block-height,
        verified: false
      }
    )
    (ok activity-id)
  )
)

;; Issue violation
(define-public (issue-violation
  (vessel-id uint)
  (zone-id uint)
  (violation-type (string-ascii 30))
  (penalty-amount uint))
  (begin
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (let ((violation-id (+ (var-get total-violations) u1)))
      (map-set violations
        { violation-id: violation-id }
        {
          vessel-id: vessel-id,
          zone-id: zone-id,
          violation-type: violation-type,
          penalty-amount: penalty-amount,
          timestamp: block-height,
          resolved: false
        }
      )
      (var-set total-violations violation-id)
      (ok violation-id)
    )
  )
)

;; Read-only functions
(define-read-only (get-vessel (vessel-id uint))
  (map-get? vessels { vessel-id: vessel-id })
)

(define-read-only (get-fishing-zone (zone-id uint))
  (map-get? fishing-zones { zone-id: zone-id })
)

(define-read-only (get-violation (violation-id uint))
  (map-get? violations { violation-id: violation-id })
)

(define-read-only (get-total-vessels)
  (var-get total-vessels)
)

(define-read-only (get-total-violations)
  (var-get total-violations)
)
