(in-package #:cl-patterns)

;; FIX: add bend?

;;; utility functions

(defun alsa-midi-panic (&key channel manually-free)
  "Stop all notes on CHANNEL, or all channels if CHANNEL is nil."
  (dolist (c (or (ensure-list channel) (iota 16)))
    (if manually-free
        (dolist (note (iota 128))
          (midihelper:send-event (midihelper:ev-noteoff c note 0)))
        (midihelper:send-event (midihelper:ev-cc c 123 0)))))

;;; cc mapping
;; http://nickfever.com/music/midi-cc-list

(defparameter *alsa-midi-channels-instruments* (make-list 16 :initial-element 0))

(defparameter *alsa-midi-cc-table* (make-hash-table)
  "Hash table mapping CC numbers to metadata and event key names to CC numbers.")

(defun set-alsa-midi-cc-mapping (cc-number description &optional event-key (mapping 'midi-truncate-clamp))
  "Set a mapping for CC-NUMBER. When EVENT-KEY is seen in an event being played by the MIDI backend, its value will be converted using the function specified by MAPPING, and then that value will be set for CC number CC-NUMBER just before the note itself is triggered. DESCRIPTION is a description of what the CC controls."
  (setf (gethash cc-number *alsa-midi-cc-table*)
        (list cc-number description event-key mapping))
  (when event-key
    (setf (gethash event-key *alsa-midi-cc-table*)
          cc-number)))

(defun get-alsa-midi-auto-cc-mapping (key)
  "Return auto-generated CC mapping parameters for a KEY of the format \"CC-N\", where N is a valid CC number."
  (let ((sym-name (symbol-name key)))
    (when (and (>= (length sym-name) 3)
               (string= "CC-" sym-name :end2 3))
      (let ((num (parse-integer (subseq sym-name 2) :junk-allowed t)))
        (when (and (integerp num)
                   (<= 0 num 127))
          (list num (format nil "CC ~s" num) key 'identity))))))

(defun get-alsa-midi-cc-mapping (key)
  "Return the CC mapping parameters for a CC number or an event key."
  (let ((key-map (or (gethash key *alsa-midi-cc-table*)
                     (get-alsa-midi-auto-cc-mapping key))))
    (if (numberp key-map)
        (gethash key-map *alsa-midi-cc-table*)
        key-map)))

(defun midi-remap-key-value (key value)
  "Remap KEY and VALUE to their equivalent MIDI CC parameter and range. Returns a list of the format (CC-NUMBER CC-VALUE), or nil if the key is not a recognized CC key."
  (if-let ((cc-mapping (get-alsa-midi-cc-mapping key)))
    (list (car cc-mapping) (funcall (nth 3 cc-mapping) value))
    (let ((sym-name (symbol-name key)))
      (if (and (>= (length sym-name) 3)
               (string= "CC-" sym-name :end2 3))
          (list (midi-truncate-clamp (parse-integer (subseq sym-name 3))) (midi-truncate-clamp value))
          nil))))

;; set default cc mappings
(mapc (lambda (x) (apply 'set-alsa-midi-cc-mapping x))
      '((1 "Vibrato/Modulation" :vibrato unipolar-1-to-midi)
        (8 "Balance" :balance bipolar-1-to-midi)
        (10 "Pan" :pan bipolar-1-to-midi)
        (71 "Resonance/Timbre" :res unipolar-1-to-midi)
        (72 "Release" :release)
        (73 "Attack" :attack)
        (74 "Cutoff/Brightness" :ffreq frequency-to-midi)
        (84 "Portamento amount" :porta)
        (91 "Reverb" :reverb)
        (92 "Tremolo" :tremolo)
        (93 "Chorus" :chorus)
        (94 "Phaser" :phaser)))

;;; backend functions

(defmethod start-backend ((backend (eql :alsa-midi)) &key)
  (unless (elt (midihelper:inspect-midihelper) 5)
    (midihelper:start-midihelper)))

(defmethod stop-backend ((backend (eql :alsa-midi)))
  (midihelper:stop-midihelper))

(defmethod backend-instrument-controls (instrument (backend (eql :alsa-midi)))
  (keys *alsa-midi-cc-table*))

(defmethod backend-all-nodes ((backend (eql :alsa-midi)))
  nil)

(defmethod backend-node-p (object (backend (eql :alsa-midi)))
  nil)

(defmethod backend-panic ((backend (eql :alsa-midi)))
  (alsa-midi-panic))

(defmethod backend-timestamps-for-event (event task (backend (eql :alsa-midi)))
  nil)

(defmethod backend-proxys-node (id (backend (eql :alsa-midi)))
  nil)

(defmethod backend-control-node-at (time (node number) params (backend (eql :alsa-midi)))
  (midihelper:ev-noteon node note velocity))

(defmethod backend-control-node-at (time node params (backend (eql :alsa-midi)))
  nil)

(defmethod backend-play-event (event task (backend (eql :alsa-midi)))
  (let* ((type (event-value event :type))
         (channel (midi-truncate-clamp (or (event-value event :channel) 0) 15))
         (pgm (midi-truncate-clamp (multiple-value-bind (value from) (event-value event :instrument)
                                     (if (eql t from)
                                         0
                                         (if (integerp value) value 0))))) ;; FIX: provide an instrument translation table to automatically translate instrument names to program numbers
         (note (midi-truncate-clamp (event-value event :midinote)))
         (velocity (unipolar-1-to-midi (event-value event :amp))) ;; FIX: maybe this shouldn't be linear?
         (time (or (raw-event-value event :timestamp-at-start) (local-time:now)))
         (extra-params (loop :for key :in (keys event)
                             :for cc-mapping := (midi-remap-key-value key (event-value event key))
                             :if cc-mapping
                               :collect cc-mapping)))
    (bt:make-thread
     (lambda ()
       (sleep (max 0 (local-time:timestamp-difference time (local-time:now))))
       (when (and pgm
                  (not (= pgm (nth channel *alsa-midi-channels-instruments*))))
         (midihelper:send-event (midihelper:ev-pgmchange channel pgm)))
       (dolist (param extra-params)
         (midihelper:send-event (midihelper:ev-cc channel (car param) (cadr param))))
       (unless (eql type :set)
         (midihelper:send-event (midihelper:ev-noteon channel note velocity))
         (sleep (max 0 (dur-time (sustain event) (tempo (slot-value task 'clock)))))
         (midihelper:send-event (midihelper:ev-noteoff channel note velocity))))
     :name "cl-patterns temporary alsa midi note thread")))

(defmethod backend-task-removed (task (backend (eql :alsa-midi)))
  ;; FIX
  )

(register-backend :alsa-midi)

;; (enable-backend :alsa-midi)

(export '(alsa-midi-panic set-alsa-midi-cc-mapping get-alsa-midi-cc-mapping))
