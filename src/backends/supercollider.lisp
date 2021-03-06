;;; supercollider.lisp - the SuperCollider/cl-collider backend for cl-patterns.
;; FIX: changing :instrument in pmono causes the old one to stay playing.
;; FIX: multichannel expansion breaks :mono

(in-package #:cl-patterns)

;;; global settings

(defvar *cl-collider-buffer-preview-synth* :spt
  "The name of the synth to use to `play' a buffer.")

;;; backend functions

(defmethod start-backend ((backend (eql :supercollider)))
  (setf cl-collider:*s* (cl-collider:make-external-server "localhost" :port 4444))
  (cl-collider:server-boot cl-collider:*s*))

(defmethod stop-backend ((backend (eql :supercollider)))
  (cl-collider:server-quit cl-collider:*s*))

(defmethod backend-instrument-controls (instrument (backend (eql :supercollider)))
  (mapcar #'car (cl-collider:synthdef-metadata instrument :controls)))

(defmethod backend-node-p (object (backend (eql :supercollider)))
  (typep object 'cl-collider::node))

(defmethod backend-timestamps-for-event (event task (backend (eql :supercollider)))
  (let ((time (if-let ((timestamp (raw-event-value event :timestamp-at-start)))
                (+ (local-time:timestamp-to-unix timestamp) (* (local-time:nsec-of timestamp) 1.0d-9))
                (cl-collider:now))))
    (list time (+ time (dur-time (sustain event))))))

(defmethod backend-proxys-node (id (backend (eql :supercollider)))
  (if (typep id 'cl-collider::node)
      id
      (gethash id (cl-collider::node-proxy-table cl-collider::*s*))))

(defmethod backend-control-node-at (time (node symbol) params (backend (eql :supercollider)))
  (cl-collider:at time
    (apply #'cl-collider:synth node params)))

(defmethod backend-control-node-at (time (node cl-collider::node) params (backend (eql :supercollider)))
  (cl-collider:at time
    (apply #'cl-collider:ctrl node params)))

(defmethod backend-convert-object ((object cl-collider::buffer) key (backend (eql :supercollider)))
  (declare (ignore key))
  (cl-collider:bufnum object))

(defmethod backend-convert-object ((object cl-collider::bus) key (backend (eql :supercollider)))
  (declare (ignore key))
  (cl-collider:busnum object))

(defmethod backend-convert-object ((object cl-collider::node) key (backend (eql :supercollider)))
  (let ((bus (if (eql key :out)
                 (cl-collider:synthdef-metadata object :input-bus)
                 (or (cl-collider:synthdef-metadata object :output-bus)
                     (cl-collider:synthdef-metadata object :input-bus)))))
    (if bus
        (cl-collider:busnum bus)
        object)))

(defmethod backend-convert-object ((object cl-collider::group) key (backend (eql :supercollider)))
  (declare (ignore key))
  (cl-collider::id object))

;;; convenience methods

(defun cl-collider-proxy (id) ;; FIX: remove this and just make `lookup-object-for-symbol' call `backend-proxys-node' for each enabled/registered backend?
  "Get the object representing the `cl-collider:proxy' with the given name."
  (backend-proxys-node id :supercollider))

(endpushnew *dictionary-lookup-functions* 'cl-collider-proxy)

(defmethod play ((object cl-collider::node))
  t)

(defmethod stop ((object cl-collider::node))
  (cl-collider:free object))

(defmethod end ((object cl-collider::node))
  (cl-collider:release object))

(defmethod playing-p ((node cl-collider::node) &optional (server cl-collider:*s*))
  (when (position (cl-collider::id node) (cl-collider::node-watcher server))
    t))

(defmethod play ((buffer cl-collider::buffer))
  (let* ((synth *cl-collider-buffer-preview-synth*)
         (synthdef-controls (mapcar #'car (cl-collider:synthdef-metadata synth :controls))))
    (play (event :backend :supercollider
                 ;; :type :note-on ;; to avoid automatically stopping it ;; FIX: implement this note type
                 :instrument synth
                 (find-if (lambda (x) ;; buffer or bufnum argument
                            (position x (list 'buffer 'bufnum) :test #'string-equal))
                          synthdef-controls)
                 (cl-collider:bufnum buffer) ;; get the actual buffer number
                 :dur 32
                 :quant 0
                 :latency 0))))

(register-backend :supercollider)

;; (enable-backend :supercollider)
