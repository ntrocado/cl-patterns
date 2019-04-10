;;; supercollider.lisp - the SuperCollider/cl-collider backend for cl-patterns.
;; FIX: changing :instrument in pmono causes the old one to stay playing.

(in-package :cl-patterns)

;;; helper functions

(defun timestamp-to-cl-collider (timestamp)
  "Convert a local-time timestamp to the format used by cl-collider."
  (+ (local-time:timestamp-to-unix timestamp) (* (local-time:nsec-of timestamp) 1.0d-9)))

(defun get-synthdef-control-names (name)
  (mapcar #'car (sc::get-synthdef-metadata name :controls)))

(defgeneric has-gate-p (item))

(defmethod has-gate-p ((item t))
  (position :gate (get-synthdef-control-names item) :test #'string-equal))

(defmethod has-gate-p ((item sc::node))
  (has-gate-p (sc::name item)))

(defmethod has-gate-p ((item string))
  (has-gate-p (alexandria:make-keyword (string-upcase item))))

(defun generate-plist-for-synth (instrument event)
  "Generate a plist of parameters for a synth based off of the synth's arguments. Unlike `event-plist', this function doesn't include event keys that aren't also one of the synth's arguments."
  (when (not (sc::get-synthdef-metadata instrument)) ;; if we don't have data for the synth, simply return a plist for the event and hope for the best.
    (return-from generate-plist-for-synth (copy-list (event-plist event))))
  (let ((synth-params (remove-if (lambda (arg) ;; for parameters unspecified by the event, we fall back to the synth's defaults, NOT the event's...
                                   (unless (string= (symbol-name arg) "SUSTAIN") ;; ...with the exception of sustain, which the synth should always get.
                                     (multiple-value-bind (value key) (event-value event arg)
                                       (declare (ignore value))
                                       (eq key t))))
                                 (get-synthdef-control-names instrument))))
    (loop :for sparam :in synth-params
       :for val = (event-value event sparam)
       :if (or (eq :gate sparam)
               (not (null val)))
       :append (list (alexandria:make-keyword sparam) (if (eq :gate sparam) 1 val)))))

(defun get-proxys-node-id (name)
  "Get the current node ID of the proxy NAME, or NIL if it doesn't exist in cl-collider's node-proxy-table."
  (if (typep name 'sc::node)
      (get-proxys-node-id (alexandria:make-keyword (string-upcase (slot-value name 'sc::name))))
      (sc::id (gethash name (sc::node-proxy-table sc::*s*)))))

(defgeneric convert-sc-object (object key)
  (:documentation "Method used to convert objects in events to values the SuperCollider server can understand. For example, any `cl-collider::buffer' objects are converted to their bufnum."))

(defmethod convert-sc-object ((object t) key)
  (declare (ignore key))
  object)

(defmethod convert-sc-object ((object sc::buffer) key)
  (declare (ignore key))
  (sc:bufnum object))

(defmethod convert-sc-object ((object sc::bus) key)
  (declare (ignore key))
  (sc:busnum object))

(defmethod convert-sc-object ((object sc::node) key)
  (let ((bus (if (eql key :out)
                 (sc:get-synthdef-metadata object :input-bus)
                 (or (sc:get-synthdef-metadata object :output-bus)
                     (sc:get-synthdef-metadata object :input-bus)))))
    (if bus
        (sc:busnum bus)
        object)))

;;; node map

(defparameter *supercollider-node-map* (make-hash-table :test 'eq)
  "Hash mapping cl-patterns tasks to SuperCollider nodes.")

(defun task-sc-nodes (task)
  (gethash task *supercollider-node-map*))

(defun (setf task-sc-nodes) (value task)
  (setf (gethash task *supercollider-node-map*) value))

;;; backend functions

(defmethod start-backend ((backend (eql :supercollider)))
  (setf sc:*s* (sc:make-external-server "localhost" :port 4444))
  (sc:server-boot *s*))

(defmethod stop-backend ((backend (eql :supercollider)))
  (sc:server-quit sc:*s*))

(defmethod backend-plays-event-p (event (backend (eql :supercollider)))
  (let ((inst (event-value event :instrument)))
    (or (gethash inst sc::*synthdef-metadata*)
        (typep inst 'sc::node))))

(defmethod backend-play-event (item task (backend (eql :supercollider)))
  "Play ITEM on the SuperCollider sound server. TASK is an internal parameter used when this function is called from the clock."
  (unless (eq (event-value item :type) :rest)
    (let* ((inst (instrument item))
           (quant (alexandria:ensure-list (quant item)))
           (offset (if (> (length quant) 2)
                       (nth 2 quant)
                       0))
           (time (+ (or (raw-event-value item :latency) *latency*)
                    (or (timestamp-to-cl-collider (raw-event-value item :timestamp-at-start)) (sc:now))
                    offset))
           (params (loop :for (key value) :on (generate-plist-for-synth inst item) :by #'cddr
                      :append (list key (convert-sc-object value key))))
           (group (event-value item :group)) ;; FIX: should be possible to auto-assign synths to groups with :group. https://github.com/ntrocado/cl-collider-examples/blob/df79d8d820581b720b8e409e819fd715a570bb0b/chapter6.lisp
           )
      (if (or (eq (event-value item :type) :mono)
              (typep inst 'sc::node))
          (let ((node (sc:at time
                        (let ((nodes (task-sc-nodes task)))
                          (cond ((not (null nodes))
                                 (apply #'sc:ctrl (car nodes) params))
                                ((typep inst 'sc::node)
                                 ;; redefining a proxy changes its Node's ID.
                                 ;; thus if the user redefines a proxy, the Node object previously provided to the pbind will become inaccurate.
                                 ;; thus we look up the proxy in the node-proxy-table to ensure we always have the correct ID.
                                 (let ((node (or (get-proxys-node-id inst)
                                                 inst)))
                                   (apply #'sc:ctrl node params)))
                                (t
                                 (apply #'sc:synth inst params)))))))
            (unless (or (typep inst 'sc::node)
                        (not (has-gate-p inst)))
              (if (< (legato item) 1)
                  (sc:at (+ time (dur-time (sustain item)))
                    (setf (task-sc-nodes task) (list))
                    (sc:release node))
                  (setf (task-sc-nodes task) (list node)))))
          (let ((node (sc:at time
                        (apply #'sc:synth inst params))))
            (when (has-gate-p node)
              (sc:at (+ time (dur-time (sustain item)))
                (sc:release node))))))))

(defmethod backend-task-removed (task (backend (eql :supercollider)))
  (let ((item (slot-value task 'item)))
    (unless (typep item 'event)
      (let ((last-output (last-output item)))
        (dolist (node (task-sc-nodes task))
          (sc:at (timestamp-to-cl-collider
                  (absolute-beats-to-timestamp (+ (slot-value task 'start-beat) (beat last-output) (sustain last-output))
                                               (slot-value task 'clock)))
            (sc:release node))))))
  (setf (task-sc-nodes task) (list)))

;;; convenience methods

(defmethod play ((object sc::node))
  t)

(defmethod stop ((object sc::node))
  (sc:stop object))

(defmethod end ((object sc::node))
  (sc:release object))

(defmethod playing-p ((node sc::node) &optional (server sc:*s*))
  (when (position (sc::node-watcher server) (sc::id node))
    t))

(register-backend :supercollider)

;; (enable-backend :supercollider)

(in-package :cl-patterns-user)

