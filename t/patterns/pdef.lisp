;;;; t/pdef.lisp - tests for `pdef' and related functionality.

(in-package #:cl-patterns/tests)

(in-suite cl-patterns-tests)

(test pdef
  "Test basic `pdef'-related functionality"
  (with-fixture temporary-pdef-dictionary ()
    (is (null (all-pdefs))
        "all-pdefs doesn't return an empty list when no pdefs are defined")
    (let* ((pat (pbind :quant 6/9))
           (pdef (pdef :x pat)))
      (is (equal (quant pat)
                 (quant pdef))
          "pdef's quant doesn't defer to its source pattern's quant when unspecified"))
    (let* ((pat (pbind :quant (list 3)))
           (pdef (pdef :x2 pat)))
      (is (progn
            (setf (quant pdef) (list 7))
            (and (equal (list 3)
                        (quant pat))
                 (equal (list 7)
                        (quant pdef))))
          "setting the quant of a pdef doesn't shadow the value of its source pattern"))
    (is (eql :x (pdef-name (pdef :x)))
        "pdef-name doesn't return the pdef's name")
    (is (eql :x (pdef-name :x))
        "pdef-name doesn't look up the pdef when provided a symbol")
    (let ((pat (pbind :foo 1)))
      (pdef :x3 pat)
      (is (eq pat (pdef-pattern (pdef :x3)))
          "pdef-pattern doesn't return the source pattern")
      (is (eq pat (pdef-pattern :x3))
          "pdef-pattern doesn't return the source pattern when provided the pdef's name"))
    ;; FIX: test `pdef-pstream' function when it's implemented?
    ;; FIX: test `pdef-task'
    (is-true (pdef-p (pdef :x))
             "pdef-p returns false for (pdef :x)")
    (is-false (pdef-p :x)
              "pdef-p returns true for for :x")
    (let* ((pat (pbind :foo 1))
           (pdef (pdef :x4 pat)))
      (is (eq pdef (find-pdef :x4))
          "find-pdef doesn't find the pdef")
      (signals no-dictionary-entry (find-pdef :does-not-exist :errorp t)
        "find-pdef doesn't signal an error when :errorp is true")
      (is-false (find-pdef :does-not-exist :errorp nil)
                "find-pdef doesn't return nil for nonexistent pdefs when :errorp is false"))
    (let ((length (length (all-pdefs))))
      (is (= 4 length)
          "all-pdefs didn't return the correct number of elements in its result (all-pdefs result length: ~S; pdef-dictionary: ~S)"
          length
          cl-patterns::*pdef-dictionary*))
    (is-true (set-equal (list :x :x2 :x3 :x4)
                        (all-pdef-names))
             "all-pdef-names does not return a list of all defined pdefs")
    (let ((the-dummy-pdef (pdef :dummy-pdef)))
      (is-true (pdef-p the-dummy-pdef)
               "The `pdef' function doesn't return a \"dummy pdef\" when called for a name that doesn't exist yet")
      (signals error
        (next the-dummy-pdef)
        "pdef doesn't signal an error when called on a \"dummy pdef\" whose pattern is not yet set")
      (pdef :dummy-pdef (pseq (list 1)))
      (is (eql 1 (next the-dummy-pdef))
          "The \"dummy pdef\" object previously acquired is not populated after the pdef pattern is set via the `pdef' function"))))
