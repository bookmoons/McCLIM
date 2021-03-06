(cl:in-package #:clim-demo)

(define-application-frame indentation ()
  ()
  (:pane :application
   :width 350
   :height 400
   :display-function #'display))

(defmethod display ((frame indentation) pane)
  (write-string "First line" pane)
  (terpri pane)

  (macrolet ((section (title &body body)
               `(progn
                  (with-drawing-options (pane :text-face :bold)
                    (write-string ,title pane))
                  (fresh-line pane)
                  (indenting-output (pane "    ")
                    (format pane "line1~%")
                    ,@body
                    (indenting-output (pane "        ")
                      (format pane "line2~%")
                      ,@body
                      (format pane "line3~%"))
                    (format pane "line4~%"))
                  (write-string "no indent" pane)
                  (terpri pane)
                  (with-room-for-graphics (pane)
                    (draw-line* pane 0 0 (rectangle-width (sheet-region pane)) 0)))))

    (section "simple"
      (format pane "Indented 1~%")
      (format pane "Indented 2~%"))

    (section "terpri"
      (write-string "Indented 1" pane)
      (terpri pane)
      (write-string "Indented 2" pane)
      (terpri pane))

    (section "#\Newline"
      (write-string "Indented 1" pane)
      (write-char #\Newline pane)
      (write-string "Indented 2" pane)
      (write-char #\Newline pane))

    (with-drawing-options (pane :ink +red+)
      (section ":ink"
        (write-string "Red" pane)
        (terpri pane)
        (with-drawing-options (pane :ink +blue+)
          (write-string "Blue" pane)
          (terpri pane))))

    (with-drawing-options (pane :text-size :small)
      (section ":text-size"
        (write-string "Small" pane)
        (terpri pane)
        (with-drawing-options (pane :text-size :large)
          (write-string "Large" pane)
          (terpri pane))))

    (with-drawing-options (pane :line-dashes '(4 4))
      (section ":line-dashes"
        (with-room-for-graphics (pane)
          (draw-line* pane 0 0 20 20))

        (with-drawing-options (pane :line-dashes '(8 4))
          (with-room-for-graphics (pane)
            (draw-line* pane 0 0 20 20)))))

    (with-drawing-options (pane :line-thickness 3)
      (section ":line-thickness"
        (with-room-for-graphics (pane)
          (draw-line* pane 0 0 20 20))

        (with-drawing-options (pane :line-thickness 5)
          (with-room-for-graphics (pane)
            (draw-line* pane 0 0 20 20)))))

    (section "table"
      (formatting-table (pane)
        (formatting-row (pane)
          (formatting-cell (pane)
            (surrounding-output-with-border (pane)
              (write-string "foo" pane)))
          (formatting-cell (pane) (write-string "bar" pane)))
        (formatting-row (pane)
          (formatting-cell (pane) (write-string "baz" pane))
          (formatting-cell (pane) (write-string "fez" pane)))))))
