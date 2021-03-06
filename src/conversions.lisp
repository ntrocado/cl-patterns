(in-package #:cl-patterns)

;;; amp/db

(defun amp-db (amp)
  "Convert amplitude to decibels."
  (* 20 (log amp 10)))

(defun db-amp (db)
  "Convert decibels to amplitude."
  (expt 10 (* db 0.05)))

;;; dur

(defun dur-time (dur &optional tempo)
  "Convert duration in beats to time in seconds according to TEMPO in beats per second."
  (/ dur (or tempo
             (and (boundp '*clock*)
                  (not (null *clock*))
                  (tempo *clock*))
             1)))

(defun time-dur (time &optional tempo)
  "Convert TIME in seconds to duration in beats according to TEMPO in beats per second."
  (* time (or tempo
              (and (boundp '*clock*)
                   (not (null *clock*))
                   (tempo *clock*))
              1)))

;;; freq/midinote/octave/root/degree

(defun midinote-freq (midinote)
  "Convert a midi note number to a frequency."
  (* 440d0 (expt 2d0 (/ (- midinote 69d0) 12))))

(defun freq-midinote (freq)
  "Convert a frequency to a midi note number."
  (+ 69d0 (* 12d0 (log (/ freq 440) 2d0))))

(defun freq-octave (freq)
  "Get the octave number that the frequency FREQ occurs in."
  (midinote-octave (freq-midinote freq)))

(defun midinote-octave (midinote)
  "Get the octave number that MIDINOTE occurs in."
  (truncate (/ midinote 12)))

(defun midinote-degree (midinote &key root octave (scale :major))
  "Get the degree of MIDINOTE, taking into account the ROOT, OCTAVE, and SCALE, if provided."
  (warn "#'midinote-degree is not done yet.")
  (let* ((notes (scale-notes (scale (scale (or scale :major)))))
         (octave (or octave (truncate (/ midinote 12))))
         (diff (- midinote (* octave 12)))
         (root (or root (- midinote ;; FIX
                           (position diff notes)))) ;; FIX
         )
    (position midinote (mapcar (lambda (n) (+ (* octave 12) root n))
                               notes))))

(defun freq-degree (freq &key root octave (scale :major))
  "Convert a frequency to a scale degree."
  (midinote-degree (freq-midinote freq)
                   :root root
                   :octave octave
                   :scale scale))

;; FIX: does having a root argument actually make sense for this?
(defun note-midinote (note &key (root 0 root-provided-p) (octave 5 octave-provided-p))
  "Given a note, return its midi note number, taking into account the ROOT and OCTAVE if provided.

See also: `note-number'"
  (etypecase note
    (number (+ root (* octave 12) note))
    (symbol (note-midinote (note-number note)))))

(defun degree-note (degree &optional (scale :major))
  "Get the relative note number in the tuning of SCALE based on the DEGREE provided."
  (let* ((scale (scale (or scale :major)))
         (notes (scale-notes scale)))
    (+ (elt-wrap notes degree)
       (* (length (tuning-pitches (tuning (scale-tuning scale))))
          (floor (/ degree (length notes)))))))

(defun degree-midinote (degree &key (root 0) (octave 5) (scale :major))
  "Get the midi note number of DEGREE, taking into account the ROOT, OCTAVE, and SCALE, if provided."
  (note-midinote (degree-note degree scale) :root root :octave octave))

(defun degree-freq (degree &key (root 0) (octave 5) (scale :major))
  "Get the frequency of DEGREE, based on the ROOT, OCTAVE, and SCALE, if provided."
  (midinote-freq (degree-midinote degree :root root :octave octave :scale scale)))

(defun ratio-midi (ratio)
  "Convert a frequency ratio to a difference in MIDI note numbers."
  (* 12 (log ratio 2)))

(defun midi-ratio (midi)
  "Convert a MIDI note number difference to a frequency ratio."
  (expt 2 (/ midi 12)))

(defun freq-rate (freq &optional (base-freq 440))
  "Convert the frequency FREQ to a playback rate, based on BASE-FREQ. Useful to convert musical pitch information to a number usable for sample playback synths."
  (/ freq base-freq))

(defun rate-freq (rate &optional (base-freq 440))
  "Convert a playback rate RATE to a frequency, based on BASE-FREQ."
  (* base-freq rate))

(defun midinote-rate (midinote &optional (base-note 69))
  "Convert a midinote to a playback rate."
  (freq-rate (midinote-freq midinote) (midinote-freq base-note)))

(defun rate-midinote (rate &optional (base-note 69))
  "Convert a playback rate to a midinote."
  (freq-midinote (rate-freq rate (midinote-freq base-note))))
