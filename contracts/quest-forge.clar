;; quest-forge.clar
;; QuestForge Task RPG: Gamified task management system on Stacks blockchain
;; This contract manages user profiles, quests, task completion tracking, and achievement rewards
;; in a role-playing game framework where real-world tasks become in-game quests.

;; =========== Error Constants ===========
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-USER-ALREADY-EXISTS (err u101))
(define-constant ERR-USER-NOT-FOUND (err u102))
(define-constant ERR-CHARACTER-ALREADY-EXISTS (err u103))
(define-constant ERR-CHARACTER-NOT-FOUND (err u104))
(define-constant ERR-QUEST-NOT-FOUND (err u105))
(define-constant ERR-QUEST-ALREADY-COMPLETED (err u106))
(define-constant ERR-INVALID-QUEST-TYPE (err u107))
(define-constant ERR-INVALID-DIFFICULTY (err u108))
(define-constant ERR-STREAK-NOT-MAINTAINED (err u109))
(define-constant ERR-ACHIEVEMENT-NOT-FOUND (err u110))

;; =========== Data Maps and Variables ===========

;; Quest types enumeration
(define-constant QUEST-TYPE-WORK u1)
(define-constant QUEST-TYPE-HEALTH u2)
(define-constant QUEST-TYPE-LEARNING u3)
(define-constant QUEST-TYPE-SOCIAL u4)
(define-constant QUEST-TYPE-CREATIVE u5)

;; Difficulty levels and corresponding XP rewards
(define-constant DIFFICULTY-EASY u1)
(define-constant DIFFICULTY-MEDIUM u2)
(define-constant DIFFICULTY-HARD u3)
(define-constant DIFFICULTY-EPIC u4)

(define-map difficulty-xp-rewards 
  uint
  uint)

;; Initialize difficulty XP rewards
(map-set difficulty-xp-rewards DIFFICULTY-EASY u10)
(map-set difficulty-xp-rewards DIFFICULTY-MEDIUM u25)
(map-set difficulty-xp-rewards DIFFICULTY-HARD u50)
(map-set difficulty-xp-rewards DIFFICULTY-EPIC u100)

;; User profile data structure
(define-map user-profiles
  principal
  {
    registered: bool,
    total-xp: uint,
    level: uint,
    quests-completed: uint,
    creation-time: uint
  })

;; Character data structure
(define-map characters
  principal
  {
    name: (string-ascii 30),
    character-class: (string-ascii 20),
    level: uint,
    xp: uint,
    strength: uint,
    intelligence: uint,
    dexterity: uint,
    creation-time: uint
  })

;; Quest data structure
(define-map quests
  {owner: principal, quest-id: uint}
  {
    title: (string-ascii 50),
    description: (string-utf8 280),
    quest-type: uint,
    difficulty: uint,
    created-at: uint,
    completed: bool,
    completed-at: uint,
    xp-reward: uint,
    recurring: bool,
    recurrence-period: uint
  })

;; Track quest counter per user
(define-map user-quest-counter
  principal
  uint)

;; Track streaks for recurring quests
(define-map quest-streaks
  {owner: principal, quest-id: uint}
  {
    current-streak: uint,
    longest-streak: uint,
    last-completed: uint
  })

;; Achievement data
(define-map achievements
  {owner: principal, achievement-id: uint}
  {
    title: (string-ascii 50),
    description: (string-utf8 280),
    xp-bonus: uint,
    unlocked-at: uint,
    badge-url: (optional (string-ascii 100))
  })

;; Track achievement counter per user
(define-map user-achievement-counter
  principal
  uint)

;; Global quest counter
(define-data-var quest-counter uint u0)

;; Global achievement counter
(define-data-var achievement-counter uint u0)

;; =========== Private Functions ===========

;; Calculate level based on XP
(define-private (calculate-level (xp uint))
  (let ((base-xp u100)
        (growth-factor u1.5))
    ;; Simple level calculation: level increases every base-xp * growth-factor^(level-1) points
    ;; This is a simplified version - actual implementation would involve more complex calculations
    (+ u1 (/ xp base-xp))))

;; Check if a quest type is valid
(define-private (is-valid-quest-type (quest-type uint))
  (or
    (is-eq quest-type QUEST-TYPE-WORK)
    (is-eq quest-type QUEST-TYPE-HEALTH)
    (is-eq quest-type QUEST-TYPE-LEARNING)
    (is-eq quest-type QUEST-TYPE-SOCIAL)
    (is-eq quest-type QUEST-TYPE-CREATIVE)))

;; Check if difficulty level is valid
(define-private (is-valid-difficulty (difficulty uint))
  (or
    (is-eq difficulty DIFFICULTY-EASY)
    (is-eq difficulty DIFFICULTY-MEDIUM)
    (is-eq difficulty DIFFICULTY-HARD)
    (is-eq difficulty DIFFICULTY-EPIC)))

;; Get XP reward for a difficulty level
(define-private (get-xp-for-difficulty (difficulty uint))
  (default-to u0 (map-get? difficulty-xp-rewards difficulty)))

;; Update user level based on new XP
(define-private (update-user-level (user principal) (additional-xp uint))
  (match (map-get? user-profiles user)
    profile
    (let ((current-xp (get total-xp profile))
          (new-xp (+ current-xp additional-xp))
          (new-level (calculate-level new-xp)))
      (map-set user-profiles user
        (merge profile {
          total-xp: new-xp,
          level: new-level
        }))
      (ok new-level))
    (err ERR-USER-NOT-FOUND)))

;; Update character stats based on quest type and difficulty
(define-private (update-character-stats (user principal) (quest-type uint) (difficulty uint))
  (match (map-get? characters user)
    character
    (let ((xp-gain (get-xp-for-difficulty difficulty))
          (new-xp (+ (get xp character) xp-gain))
          (new-level (calculate-level new-xp))
          
          ;; Different quest types improve different attributes
          (strength-gain (if (is-eq quest-type QUEST-TYPE-HEALTH) difficulty u0))
          (intelligence-gain (if (is-eq quest-type QUEST-TYPE-LEARNING) difficulty u0))
          (dexterity-gain (if (is-eq quest-type QUEST-TYPE-WORK) difficulty u0)))
      
      (map-set characters user
        (merge character {
          xp: new-xp,
          level: new-level,
          strength: (+ (get strength character) strength-gain),
          intelligence: (+ (get intelligence character) intelligence-gain),
          dexterity: (+ (get dexterity character) dexterity-gain)
        }))
      (ok new-level))
    (err ERR-CHARACTER-NOT-FOUND)))

;; Update streak for recurring quests
(define-private (update-quest-streak (owner principal) (quest-id uint) (quest-details (tuple (recurring bool) (recurrence-period uint))))
  (let ((current-time (unwrap-panic (get-block-info? time (- block-height u1)))))
    (match (map-get? quest-streaks {owner: owner, quest-id: quest-id})
      streak-data
      (let ((last-completed (get last-completed streak-data))
            (allowed-window (+ last-completed (* (get recurrence-period quest-details) u86400))) ;; Convert days to seconds
            (current-streak (get current-streak streak-data))
            (longest-streak (get longest-streak streak-data)))
        
        ;; Check if completed within the recurrence period
        (if (and (get recurring quest-details) (<= current-time allowed-window))
          (let ((new-current-streak (+ current-streak u1))
                (new-longest-streak (if (> new-current-streak longest-streak)
                                      new-current-streak
                                      longest-streak)))
            (map-set quest-streaks {owner: owner, quest-id: quest-id}
              {
                current-streak: new-current-streak,
                longest-streak: new-longest-streak,
                last-completed: current-time
              })
            (ok true))
          ;; Streak broken - reset if recurring quest
          (if (get recurring quest-details)
            (begin
              (map-set quest-streaks {owner: owner, quest-id: quest-id}
                {
                  current-streak: u1, ;; Start a new streak
                  longest-streak: longest-streak,
                  last-completed: current-time
                })
              (ok false))
            (ok true))))
      
      ;; No streak data yet - initialize
      (begin
        (map-set quest-streaks {owner: owner, quest-id: quest-id}
          {
            current-streak: u1,
            longest-streak: u1,
            last-completed: current-time
          })
        (ok true)))))

;; Check for and award achievements
(define-private (check-achievements (owner principal))
  (let ((profile (unwrap! (map-get? user-profiles owner) (err ERR-USER-NOT-FOUND)))
        (quests-completed (get quests-completed profile))
        (level (get level profile))
        (achievement-count (default-to u0 (map-get? user-achievement-counter owner))))
    
    ;; Achievement checks based on quest completion milestones
    ;; These are just examples - can be expanded as needed
    (if (and (>= quests-completed u10) 
             (is-none (map-get? achievements {owner: owner, achievement-id: u1})))
      (award-achievement owner u1 "Busy Bee" "Completed 10 quests" u50 none)
      (ok true))
    
    ;; Achievement for reaching level milestones
    (if (and (>= level u5)
             (is-none (map-get? achievements {owner: owner, achievement-id: u2})))
      (award-achievement owner u2 "Rising Star" "Reached level 5" u100 none)
      (ok true))
    
    ;; Add more achievement checks as needed
    (ok achievement-count)))

;; Award an achievement to a user
(define-private (award-achievement 
  (owner principal) 
  (id uint) 
  (title (string-ascii 50)) 
  (description (string-utf8 280)) 
  (xp-bonus uint)
  (badge-url (optional (string-ascii 100))))
  
  (let ((current-time (unwrap-panic (get-block-info? time (- block-height u1))))
        (achievement-count (default-to u0 (map-get? user-achievement-counter owner)))
        (next-id (if (> id u0) id (+ achievement-count u1))))
    
    ;; Record the achievement
    (map-set achievements {owner: owner, achievement-id: next-id}
      {
        title: title,
        description: description,
        xp-bonus: xp-bonus,
        unlocked-at: current-time,
        badge-url: badge-url
      })
    
    ;; Update achievement counter if using auto-increment
    (if (is-eq id u0)
      (map-set user-achievement-counter owner (+ achievement-count u1))
      (ok true))
    
    ;; Award XP bonus
    (update-user-level owner xp-bonus)
    
    (ok next-id)))

;; =========== Read-Only Functions ===========

;; Get user profile
(define-read-only (get-user-profile (user principal))
  (map-get? user-profiles user))

;; Get character data
(define-read-only (get-character (user principal))
  (map-get? characters user))

;; Get quest details
(define-read-only (get-quest (owner principal) (quest-id uint))
  (map-get? quests {owner: owner, quest-id: quest-id}))

;; Get user's quest count
(define-read-only (get-user-quest-count (user principal))
  (default-to u0 (map-get? user-quest-counter user)))

;; Get quest streak information
(define-read-only (get-streak-info (owner principal) (quest-id uint))
  (map-get? quest-streaks {owner: owner, quest-id: quest-id}))

;; Get achievement details
(define-read-only (get-achievement (owner principal) (achievement-id uint))
  (map-get? achievements {owner: owner, achievement-id: achievement-id}))

;; Get user's achievement count
(define-read-only (get-user-achievement-count (user principal))
  (default-to u0 (map-get? user-achievement-counter user)))

;; Check if user exists
(define-read-only (user-exists (user principal))
  (match (map-get? user-profiles user)
    profile (is-eq (get registered profile) true)
    false))

;; Check if character exists
(define-read-only (character-exists (user principal))
  (is-some (map-get? characters user)))

;; =========== Public Functions ===========

;; Register a new user
(define-public (register-user)
  (let ((user tx-sender)
        (current-time (unwrap-panic (get-block-info? time (- block-height u1)))))
    
    ;; Check if user already exists
    (asserts! (not (user-exists user)) ERR-USER-ALREADY-EXISTS)
    
    ;; Create user profile
    (map-set user-profiles user
      {
        registered: true,
        total-xp: u0,
        level: u1,
        quests-completed: u0,
        creation-time: current-time
      })
    
    ;; Initialize counters
    (map-set user-quest-counter user u0)
    (map-set user-achievement-counter user u0)
    
    (ok true)))

;; Create a character
(define-public (create-character 
  (name (string-ascii 30)) 
  (character-class (string-ascii 20)) 
  (initial-strength uint) 
  (initial-intelligence uint) 
  (initial-dexterity uint))
  
  (let ((user tx-sender)
        (current-time (unwrap-panic (get-block-info? time (- block-height u1)))))
    
    ;; Ensure user is registered
    (asserts! (user-exists user) ERR-USER-NOT-FOUND)
    
    ;; Ensure character doesn't already exist
    (asserts! (not (character-exists user)) ERR-CHARACTER-ALREADY-EXISTS)
    
    ;; Initial stat points should be distributed within limits
    (asserts! (<= (+ (+ initial-strength initial-intelligence) initial-dexterity) u15) (err u111))
    
    ;; Create character
    (map-set characters user
      {
        name: name,
        character-class: character-class,
        level: u1,
        xp: u0,
        strength: initial-strength,
        intelligence: initial-intelligence,
        dexterity: initial-dexterity,
        creation-time: current-time
      })
    
    (ok true)))

;; Create a new quest
(define-public (create-quest 
  (title (string-ascii 50)) 
  (description (string-utf8 280)) 
  (quest-type uint) 
  (difficulty uint)
  (recurring bool)
  (recurrence-period uint))
  
  (let ((user tx-sender)
        (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
        (user-quests (default-to u0 (map-get? user-quest-counter user)))
        (next-quest-id (+ user-quests u1))
        (xp-reward (get-xp-for-difficulty difficulty)))
    
    ;; Ensure user is registered
    (asserts! (user-exists user) ERR-USER-NOT-FOUND)
    
    ;; Validate quest type
    (asserts! (is-valid-quest-type quest-type) ERR-INVALID-QUEST-TYPE)
    
    ;; Validate difficulty
    (asserts! (is-valid-difficulty difficulty) ERR-INVALID-DIFFICULTY)
    
    ;; Create the quest
    (map-set quests {owner: user, quest-id: next-quest-id}
      {
        title: title,
        description: description,
        quest-type: quest-type,
        difficulty: difficulty,
        created-at: current-time,
        completed: false,
        completed-at: u0,
        xp-reward: xp-reward,
        recurring: recurring,
        recurrence-period: recurrence-period
      })
    
    ;; Update user's quest counter
    (map-set user-quest-counter user next-quest-id)
    
    ;; Increment global quest counter
    (var-set quest-counter (+ (var-get quest-counter) u1))
    
    (ok next-quest-id)))

;; Complete a quest
(define-public (complete-quest (quest-id uint))
  (let ((user tx-sender)
        (current-time (unwrap-panic (get-block-info? time (- block-height u1)))))
    
    ;; Ensure user is registered
    (asserts! (user-exists user) ERR-USER-NOT-FOUND)
    
    ;; Retrieve quest
    (match (map-get? quests {owner: user, quest-id: quest-id})
      quest-data
      (begin
        ;; Ensure quest isn't already completed (unless recurring)
        (asserts! (or (get recurring quest-data) (not (get completed quest-data))) ERR-QUEST-ALREADY-COMPLETED)
        
        ;; Get XP reward
        (let ((xp-reward (get xp-reward quest-data)))
          
          ;; Update streak for recurring quests
          (if (get recurring quest-data)
            (update-quest-streak user quest-id (tuple (recurring (get recurring quest-data)) (recurrence-period (get recurrence-period quest-data))))
            (ok true))
          
          ;; Mark quest as completed
          (map-set quests {owner: user, quest-id: quest-id}
            (merge quest-data {
              completed: true,
              completed-at: current-time
            }))
          
          ;; Update user profile
          (match (map-get? user-profiles user)
            profile
            (map-set user-profiles user 
              (merge profile {
                quests-completed: (+ (get quests-completed profile) u1)
              }))
            (err ERR-USER-NOT-FOUND))
          
          ;; Award XP to user
          (update-user-level user xp-reward)
          
          ;; Update character stats based on quest type
          (update-character-stats user (get quest-type quest-data) (get difficulty quest-data))
          
          ;; Check for achievements
          (check-achievements user)
          
          (ok xp-reward)))
      (err ERR-QUEST-NOT-FOUND))))

;; Update quest details (only for uncompleted quests)
(define-public (update-quest
  (quest-id uint)
  (title (string-ascii 50))
  (description (string-utf8 280))
  (quest-type uint)
  (difficulty uint)
  (recurring bool)
  (recurrence-period uint))
  
  (let ((user tx-sender))
    
    ;; Ensure user is registered
    (asserts! (user-exists user) ERR-USER-NOT-FOUND)
    
    ;; Validate quest type and difficulty
    (asserts! (is-valid-quest-type quest-type) ERR-INVALID-QUEST-TYPE)
    (asserts! (is-valid-difficulty difficulty) ERR-INVALID-DIFFICULTY)
    
    ;; Retrieve quest
    (match (map-get? quests {owner: user, quest-id: quest-id})
      quest-data
      (begin
        ;; Ensure quest isn't already completed
        (asserts! (not (get completed quest-data)) ERR-QUEST-ALREADY-COMPLETED)
        
        ;; Update quest
        (map-set quests {owner: user, quest-id: quest-id}
          (merge quest-data {
            title: title,
            description: description,
            quest-type: quest-type,
            difficulty: difficulty,
            xp-reward: (get-xp-for-difficulty difficulty),
            recurring: recurring,
            recurrence-period: recurrence-period
          }))
        
        (ok true))
      (err ERR-QUEST-NOT-FOUND))))

;; Delete a quest (only uncompleted quests)
(define-public (delete-quest (quest-id uint))
  (let ((user tx-sender))
    
    ;; Ensure user is registered
    (asserts! (user-exists user) ERR-USER-NOT-FOUND)
    
    ;; Retrieve quest
    (match (map-get? quests {owner: user, quest-id: quest-id})
      quest-data
      (begin
        ;; Ensure quest isn't completed
        (asserts! (not (get completed quest-data)) ERR-QUEST-ALREADY-COMPLETED)
        
        ;; Delete quest (we don't actually delete, just mark it completed with special flag)
        (map-set quests {owner: user, quest-id: quest-id}
          (merge quest-data {
            completed: true,
            completed-at: u0  ;; Special flag to indicate deletion rather than completion
          }))
        
        (ok true))
      (err ERR-QUEST-NOT-FOUND))))

;; Reset a recurring quest to be completed again
(define-public (reset-recurring-quest (quest-id uint))
  (let ((user tx-sender))
    
    ;; Ensure user is registered
    (asserts! (user-exists user) ERR-USER-NOT-FOUND)
    
    ;; Retrieve quest
    (match (map-get? quests {owner: user, quest-id: quest-id})
      quest-data
      (begin
        ;; Ensure quest is recurring and completed
        (asserts! (and (get recurring quest-data) (get completed quest-data)) (err u112))
        
        ;; Reset quest to uncompleted state
        (map-set quests {owner: user, quest-id: quest-id}
          (merge quest-data {
            completed: false,
            completed-at: u0
          }))
        
        (ok true))
      (err ERR-QUEST-NOT-FOUND))))

;; Update character attributes
(define-public (update-character
  (name (string-ascii 30))
  (character-class (string-ascii 20)))
  
  (let ((user tx-sender))
    
    ;; Ensure user is registered
    (asserts! (user-exists user) ERR-USER-NOT-FOUND)
    
    ;; Retrieve character
    (match (map-get? characters user)
      character-data
      (begin
        ;; Update character
        (map-set characters user
          (merge character-data {
            name: name,
            character-class: character-class
          }))
        
        (ok true))
      (err ERR-CHARACTER-NOT-FOUND))))

;; Create a custom achievement (for testing or admin purposes)
;; In a production system, this would have proper authorization controls
(define-public (create-custom-achievement
  (owner principal)
  (title (string-ascii 50))
  (description (string-utf8 280))
  (xp-bonus uint)
  (badge-url (optional (string-ascii 100))))
  
  (let ((caller tx-sender))
    ;; For now, anyone can create achievements (would be restricted in production)
    ;; This could be expanded with a check against an admin list
    
    ;; Ensure target user exists
    (asserts! (user-exists owner) ERR-USER-NOT-FOUND)
    
    ;; Award the achievement
    (award-achievement owner u0 title description xp-bonus badge-url)))