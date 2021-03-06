(in-package #:cl-patterns/tests)

(in-suite cl-patterns-tests)

(test gete
  "Test the `gete' function"
  (is (equal (iota *max-pattern-yield-length*)
             (cl-patterns::gete (next-upto-n (pbind :foo (pseries))) :foo))
      "gete returns incorrect results"))

(test string-keyword
  "Test the `string-keyword' function"
  (is (eql :foo
           (cl-patterns::string-keyword "foo"))
      "string-keyword doesn't convert strings to keywords correctly"))

(test normalized-sum
  "Test the `normalized-sum' function"
  (is (= 1
         (reduce #'+ (cl-patterns::normalized-sum (list 0 1 2 3 4 5))))
      "normalized-sum returns a list whose elements add up to 1"))

(test cumulative-list
  "Test the `cumulative-list' function"
  (is (equal (list 0 0 2 4 7)
             (cl-patterns::cumulative-list (list 0 0 2 2 3)))
      "cumulative-list returns incorrect results"))

(test index-of-greater-than
  "Test the `index-of-greater-than' function"
  (is (= 4
         (cl-patterns::index-of-greater-than 3 (list 1 2 3 3 4 4)))
      "index-of-greater-than returns incorrect results"))

(test mapcar-longest
  "Test the `mapcar-longest' function"
  (is (equal (list 1 3 3)
             (cl-patterns::mapcar-longest #'+ (list 0 1) (list 1) (list 0 1 2)))
      "mapcar-longest returns incorrect results")
  (is (equal (list 0 2 2 4 4 6)
             (cl-patterns::mapcar-longest #'+ (list 0 1) (list 0 1 2 3 4 5)))
      "mapcar-longest doesn't wrap indexes of the shorter lists correctly"))

(test multi-channel-funcall
  "Test the `multi-channel-funcall' function"
  (is (equal 3
             (cl-patterns::multi-channel-funcall #'+ 2 1))
      "multi-channel-funcall doesn't return a lone value when all its inputs are lone values"))

(test most-x
  "Test the `most-x' function"
  (is (equal (list 1 2 3)
             (cl-patterns::most-x (list (list 1) (list 1 2 3) (list 1 2)) #'> #'length))
      "most-x returns incorrect results"))

(test plist-set
  "Test the `plist-set' function"
  (is (equal (list :foo :bar :baz :qux)
             (cl-patterns::plist-set (list :foo :bar) :baz :qux))
      "plist-set returns incorrect results")
  (is (null (cl-patterns::plist-set (list :foo :bar) :foo nil))
      "plist-set doesn't remove items from the plist when VALUE is nil"))

(test seq
  "Test the `seq' function"
  (is (equal (list 0 1 2 3)
             (seq :start 0 :end 3))
      "seq doesn't work correctly when START is lower than END")
  (is (equal (list 20 19 18 17 16 15 14 13 12 11 10 9 8 7 6 5 4 3)
             (seq :start 20 :end 3))
      "seq doesn't work correctly when START is higher than END")
  (is (equal (list 0 2 4 6)
             (seq :start 0 :step 2 :end 6))
      "seq doesn't work correctly with START, STEP, and END"))

(test seq-range
  "Test the `seq-range' function"
  ;; FIX
  )

(test next-beat-for-quant
  "Test the `next-beat-for-quant' function"
  (is-true (= 0 (next-beat-for-quant 4 0))
           "next-beat-for-quant returned the wrong result")
  (is-true (= 4 (next-beat-for-quant 4 2))
           "next-beat-for-quant returned the wrong result")
  (is-true (= 5 (next-beat-for-quant (list 4 1) 3))
           "next-beat-for-quant returned the wrong result for a QUANT with phase")
  (is-true (= 3 (next-beat-for-quant (list 4 -1) 3))
           "next-beat-for-quant returned the wrong result for a QUANT with negative phase")
  (is-true (= 1 (next-beat-for-quant 0.25 1.1 -1))
           "next-beat-for-quant returned the wrong result for a negative DIRECTION")
  ;; FIX: test more of the negative DIRECTION
  )

(test beat
  "Test the `beat' function"
  (is (= 8
         (let ((pstr (as-pstream (pbind :dur (pn 1 8)))))
           (next-upto-n pstr)
           (beat pstr)))
      "beat returns incorrect results")
  (is-true (equal (list 0 1 2 3)
                  (gete (next-n (pbind :dur 1 :x (pfunc (lambda () (beat *event*)))) 4) :x))
           "*event*'s beat is not correct in patterns"))

(test keys
  "Test cl-patterns `keys' methods"
  (is (equal (list :foo :bar)
             (cl-patterns::keys (event :foo 1 :bar 2)))
      "keys doesn't work correctly for events"))
