(in-package :mcclim-render)

(declaim (optimize speed))

#|
Convert an ink into an rgba design function.
An rbga design function return a rgba color for a given point (x,y)
It is done in two steps.
Firstly an ink is converted into a rgba design (uniform-rgba-design or functional-rgba-design).
Secondly, an rgba design is converted into a function.
|#

;;;
;;; protocol
;;;

(defgeneric make-rgba-design-fn (rgba-design))
(defgeneric make-rgba-design (ink))

(deftype design-fn () '(function (fixnum fixnum) (values octet octet octet octet)))

(defparameter *foreground-design* nil)
(defparameter *background-design* nil)

;;;
;;; Design structure
;;;

(defstruct uniform-rgba-design
  (red 0 :type octet)
  (green 0 :type octet)
  (blue 0 :type octet)
  (alpha 0 :type octet)
  mask)

(defstruct functional-rgba-design
  color-fn
  mask)

;;;
;;; make a design function
;;;

(defmethod make-rgba-design-fn ((rgba-design uniform-rgba-design))
  (let ((mask (uniform-rgba-design-mask rgba-design))
	(red (uniform-rgba-design-red rgba-design))
	(green (uniform-rgba-design-green rgba-design))
	(blue (uniform-rgba-design-blue rgba-design))
	(alpha (uniform-rgba-design-alpha rgba-design)))
    (if mask
	(lambda (x y)
	  (if (clim:region-contains-position-p mask x y)
	      (values red green blue alpha)
	      (values 0 0 0 0)))
	(lambda (x y)
	  (declare (ignore x y))
	  (values red green blue alpha)))))

(defmethod make-rgba-design-fn ((rgba-design functional-rgba-design))
  (let ((mask (functional-rgba-design-mask rgba-design))
	(fn (functional-rgba-design-color-fn rgba-design)))
    (declare (type design-fn fn))
    (if mask
	(lambda (x y)
	  (if (clim:region-contains-position-p mask x y)
	      (funcall fn x y)
	      (values 0 0 0 0)))
	(lambda (x y)
	  (funcall fn x y)))))

(defmethod make-rgba-design-fn ((design design))
  (make-rgba-design-fn (make-rgba-design design)))

;;;
;;; Make a rgba design
;;;

(defmethod make-rgba-design (ink)
  (error "unknow how to make an rgba design of the ~A" ink))

(defmethod make-rgba-design ((ink named-color))
  (multiple-value-bind (red green blue) (color-rgb ink)
    (make-uniform-rgba-design
     :red (color-value->octet red)
     :green (color-value->octet green)
     :blue (color-value->octet blue)
     :alpha 255)))

(defmethod make-rgba-design ((ink (eql +foreground-ink+)))
  (make-rgba-design *foreground-design*))

(defmethod make-rgba-design ((ink (eql +background-ink+)))
  (make-rgba-design *background-design*))

(defun make-flipping-fn (design1 design2)
  (let ((d1 (make-rgba-design-fn design1))
	(d2 (make-rgba-design-fn design2)))
    (declare (type design-fn d1 d2))
    (make-functional-rgba-design
     :color-fn (lambda (x y)
		 (multiple-value-bind (r.d1 g.d1 b.d1 a.d1)
		     (funcall d1 x y)
		   (declare (ignore a.d1))
		   (multiple-value-bind (r.d2 g.d2 b.d2 a.d2)
		       (funcall d2 x y)
		     (declare (ignore a.d2))
		     (values
		      (logxor r.d1 r.d2)
		      (logxor g.d1 g.d2)
		      (logxor b.d1 b.d2)
		      255)))))))

(defmethod make-rgba-design ((ink (eql +flipping-ink+)))
  (make-flipping-fn *background-design* *foreground-design*))

(defmethod make-rgba-design ((ink standard-flipping-ink))
  (with-slots (climi::design1 climi::design2) ink
    (make-flipping-fn climi::design1 climi::design2)))

(defmethod  make-rgba-design ((ink %transparent-ink))
  (make-uniform-rgba-design
   :red 0
   :green 0
   :blue 0
   :alpha 0))

(defmethod make-rgba-design ((ink standard-opacity))
  (make-uniform-rgba-design
   :red 255
   :green 255
   :blue 255
   :alpha (color-value->octet (opacity-value ink))))

(defmethod make-rgba-design ((ink indexed-pattern))
  (let ((designs (map 'vector #'(lambda (ink)
				  (make-rgba-design-fn ink))
		      (pattern-designs ink))))
    (declare (type (simple-array design-fn (*)) designs))
    (make-functional-rgba-design
     :color-fn (lambda (x y)
		 (funcall (elt designs (aref (pattern-array ink) y x)) x y))
     :mask (make-rectangle* 0 0
			    (1- (clim:pattern-width ink))
			    (1- (clim:pattern-height ink))))))

(defmethod make-rgba-design ((ink rgb-pattern))
  (let* ((img (slot-value ink 'image))
	 (data (image-data img)))
    (declare (type clim-rgb-image-data data))

        (make-functional-rgba-design
         :color-fn (if (mcclim-image::image-alpha-p img)
                       (lambda (x y)
                         (let ((p (aref data y  x)))
                           (let ((r.bg (ldb (byte 8 0) p))
                                 (g.bg (ldb (byte 8 8) p))
                                 (b.bg (ldb (byte 8 16) p))
                                 (a.bg (ldb (byte 8 24) p)))
                             (values
                              r.bg g.bg b.bg a.bg))))
                       (lambda (x y)
                         (let ((p (aref data y  x)))
                           (let ((r.bg (ldb (byte 8 0) p))
                                 (g.bg (ldb (byte 8 8) p))
                                 (b.bg (ldb (byte 8 16) p)))
                             (values
                              r.bg g.bg b.bg 255)))))
         :mask (make-rectangle* 0 0
                                (1- (clim:pattern-width ink))
                                (1- (clim:pattern-height ink))))))

(defmethod make-rgba-design ((ink rectangular-tile))
  (let ((design (make-rgba-design-fn (rectangular-tile-design ink)))
	(width (rectangular-tile-width ink))
	(height (rectangular-tile-height ink)))
    (declare (type design-fn design)
             (type fixnum width height))
    (make-functional-rgba-design
     :color-fn (lambda (x y)
                 (declare (type fixnum x y))
		 (funcall design (mod x width) (mod y height))))))

(defmethod make-rgba-design ((ink transformed-design))
  (let ((design (make-rgba-design (transformed-design-design ink)))
        (transformation (invert-transformation (transformed-design-transformation ink))))
    (if (typep design 'uniform-rgba-design)
        design
        (let ((design-fn (make-rgba-design-fn design)))
          (declare (type design-fn design-fn))
          (make-functional-rgba-design
           :color-fn (lambda (x y)
                       (declare (type fixnum x y))
                       (with-transformed-position (transformation x y)
                         (funcall design-fn (floor x) (floor y)))))))))

(defgeneric compose-in-rgba-design (ink mask)
  (:method (ink mask)
    (let ((mask-fn (make-rgba-design-fn mask))
	  (ink-fn (make-rgba-design-fn ink)))
      (declare (type design-fn ink-fn mask-fn))
      (make-functional-rgba-design
       :color-fn (lambda (x y)
		   (multiple-value-bind (r1 g1 b1 a1)
		       (funcall ink-fn x y)
		     (multiple-value-bind (r2 g2 b2 a2)
			 (funcall mask-fn x y)
		       (declare (ignore r2 g2 b2))
		       (values r1 g1 b1 (octet-mult a1 a2))))))))
  (:method ((ink uniform-rgba-design) (mask uniform-rgba-design))
    (make-uniform-rgba-design
     :red (uniform-rgba-design-red ink)
     :green (uniform-rgba-design-green ink)
     :blue (uniform-rgba-design-blue ink)
     :alpha (octet-mult (uniform-rgba-design-alpha ink)
                        (uniform-rgba-design-alpha mask)))))

(defgeneric compose-out-rgba-design (ink mask)
  (:method (ink mask)
    (let ((mask-fn (make-rgba-design-fn mask))
	  (ink-fn (make-rgba-design-fn ink)))
      (declare (type design-fn ink-fn mask-fn))
      (make-functional-rgba-design
       :color-fn (lambda (x y)
		   (multiple-value-bind (r1 g1 b1 a1)
		       (funcall ink-fn x y)
		     (multiple-value-bind (r2 g2 b2 a2)
			 (funcall mask-fn x y)
		       (declare (ignore r2 g2 b2))
		       (values r1 g1 b1 (octet-mult a1 (- 255 a2)))))))))
  (:method ((ink uniform-rgba-design) (mask uniform-rgba-design))
    (make-uniform-rgba-design
     :red (uniform-rgba-design-red ink)
     :green (uniform-rgba-design-green ink)
     :blue (uniform-rgba-design-blue ink)
     :alpha (octet-mult (uniform-rgba-design-alpha ink)
                        (- 255 (uniform-rgba-design-alpha mask))))))

(defgeneric compose-over-rgba-design (fore back)
  (:method (fore back)
    (let ((fore-fn (make-rgba-design-fn fore))
	  (back-fn (make-rgba-design-fn back)))
      (declare (type design-fn fore-fn back-fn))
      (make-functional-rgba-design
       :color-fn (lambda (x y)
 		   (multiple-value-bind (r1 g1 b1 a1)
		       (funcall fore-fn x y)
		     (multiple-value-bind (r2 g2 b2 a2)
			 (funcall back-fn x y)
		         (multiple-value-bind (red green blue alpha)
			     (octet-blend-function 
			      r1 g1 b1 a1 r2 g2 b2 a2)
			   (values red green blue alpha))))))))
  (:method ((fore uniform-rgba-design) (back uniform-rgba-design))
    (multiple-value-bind (red green blue alpha)
        (octet-blend-function
         (uniform-rgba-design-red fore)
         (uniform-rgba-design-green fore)
         (uniform-rgba-design-blue fore)
         (uniform-rgba-design-alpha fore)
         (uniform-rgba-design-red back)
         (uniform-rgba-design-green back)
         (uniform-rgba-design-blue back)
         (uniform-rgba-design-alpha back))
      (make-uniform-rgba-design
       :red red
       :green green
       :blue blue
       :alpha alpha))))

(defmethod make-rgba-design ((ink in-compositum))
  (let ((c-ink (make-rgba-design (compositum-ink ink)))
	(c-mask (make-rgba-design (compositum-mask ink))))
    (compose-in-rgba-design c-ink c-mask)))

(defmethod make-rgba-design ((ink out-compositum))
  (let ((c-ink (make-rgba-design (compositum-ink ink)))
	(c-mask (make-rgba-design (compositum-mask ink))))
    (compose-out-rgba-design c-ink c-mask)))

(defmethod make-rgba-design ((ink over-compositum))
  (let ((c-fore (make-rgba-design (compositum-foreground ink)))
	(c-back (make-rgba-design (compositum-background ink))))
    (compose-over-rgba-design c-fore c-back)))


;;;
;;; design fix
;;;

(defmethod clim:transform-region (transformation (design named-color))
  design)

(defmethod clim:transform-region (transformation (design standard-flipping-ink))
  design)
