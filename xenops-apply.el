;; -*- lexical-binding: t -*-

(setq xenops-apply-post-apply-hook nil)

(defmacro xenops-define-apply-command (op-type docstring)
  `(defun ,(intern (concat "xenops-" (symbol-name op-type))) ()
     ,(concat docstring " "
              "The elements operated on are determined by trying the following:
1. The element at point, if any.
2. Elements in the active region, if there is an active region.
3. All elements in the buffer.")
     (interactive)
     (xenops-apply '(,op-type))))

(defmacro xenops-define-apply-at-point-command (op docstring)
  `(defun ,(intern (concat "xenops-" (symbol-name op) "-at-point")) ()
     ,docstring
     (interactive)
     (-if-let* ((el (xenops-apply-parse-at-point))
                (handlers (xenops-ops-get ',op :handlers)))
         (xenops-element-dispatch el handlers))))

(defun xenops-apply (ops &optional pred)
  "Apply operation types OPS to any elements encountered. The
region operated on is either the active region, or the entire
buffer.

Optional argument PRED is a function taking an element plist as
its only argument. The element will be operated on iff PRED
returns non-nil."
  (let ((handlers (xenops-ops-get-for-ops ops :handlers)))
    (cl-destructuring-bind (beg end region-active)
        (if (region-active-p)
            `(,(region-beginning) ,(region-end) t)
          `(,(point-min) ,(point-max) nil))
      (xenops-apply-handlers handlers beg end region-active pred)
      (run-hook-with-args 'xenops-apply-post-apply-hook ops beg end region-active pred))))

(defun xenops-apply-at-point (ops &optional pred)
  "Apply operation types OPS to element at point, if there is one."
  (xenops-apply-handlers-at-point (xenops-ops-get-for-ops ops :handlers) pred))

(defun xenops-apply-handlers (handlers beg end region-active &optional pred)
  "Apply HANDLERS to any elements encountered. The region
operated on is either the active region, or the entire buffer."
  (cl-flet ((handle (lambda (el) (save-excursion
                              (xenops-element-dispatch el handlers)))))
    (save-excursion
      (goto-char beg)
      (let ((parse-at-point-fns (xenops-elements-get-all :parser))
            (sem-start-value (aref xenops-math-latex-tasks-semaphore 1)))
        (while (setq el (xenops-apply-get-next-element nil end parse-at-point-fns))
          (and el
               (or (null pred) (funcall pred el))
               (ignore-errors (handle el))))
        (if (-intersection handlers '(xenops-math-render))
            (message "Started %d latex processing tasks"
                     (- sem-start-value
                        (aref xenops-math-latex-tasks-semaphore 1))))))))

(defun xenops-apply-handlers-at-point (handlers &optional pred)
  "Apply HANDLERS to element at point if there is one."
  (cl-flet ((handle (lambda (el) (save-excursion
                              (xenops-element-dispatch el handlers)))))
    (-when-let* ((el (xenops-apply-parse-at-point)))
      (handle el)
      t)))

(defun xenops-apply-get-next-element (&optional start-regexp end parse-at-point-fns)
  "If there is another element, return it and leave point after it.
An element is a plist containing data about a regexp match for a
section of the buffer that Xenops can do something to."
  (let ((start-regexp (or start-regexp (xenops-elements-delimiter-start-regexp)))
        (end (or end (point-max)))
        (parse-at-point-fns (or parse-at-point-fns (xenops-elements-get-all :parser))))
    (-if-let* ((_ (re-search-forward start-regexp end t))
               (_ (goto-char (match-beginning 0)))
               (element (xenops-apply-parse-at-point parse-at-point-fns))
               (_ (goto-char (plist-get element :end))))
        element)))

(defun xenops-apply-parse-at-point (&optional parse-at-point-fns)
  "Return the element at point if there is one."
  ;; If there's a xenops overlay at point, then the user will expect that element to be returned,
  ;; even if point somehow isn't actually on the element.
  (-if-let* ((ov (and (not parse-at-point-fns) (xenops-overlay-at-point))))
      (save-excursion (goto-char (overlay-start ov))
                      (xenops-apply-get-next-element nil (overlay-end ov)))
    (xenops-util-first-result #'funcall (or parse-at-point-fns
                                            (xenops-elements-get-all :parser)))))

(defun xenops-apply-post-apply-deactivate-mark (ops beg end region-active pred)
  "Deactivate mark when appropriate.

`increase-size` and `decrease-size` are expected to be applied
multiple times, and we want to preserve the active region.
Otherwise, the region should be deactivated after operating on
it."
  (and region-active (not (-intersection ops '(increase-size decrease-size)))
       (deactivate-mark)))

(defun xenops-apply-post-apply-track-image-size-changes (ops beg end region-active pred)
  "Track image size changes so that new images are displayed with the correct size."
  ;; Hack: In some sense we want a new image to have the expected size, given any changes to image
  ;; size that have been applied to existing images. Here we track the overall image scale, paying
  ;; attention only when a user has resized all the images in the buffer, i.e. not when region is
  ;; active.
  (unless region-active
    (cond
     ((eq ops '(increase-size))
      (setq xenops-math-image-current-scale-factor (* xenops-math-image-current-scale-factor
                                                      xenops-math-image-change-size-factor)))
     ((eq ops '(decrease-size))
      (setq xenops-math-image-current-scale-factor (/ xenops-math-image-current-scale-factor
                                                      xenops-math-image-change-size-factor))))))

(add-hook 'xenops-apply-post-apply-hook #'xenops-apply-post-apply-deactivate-mark)
(add-hook 'xenops-apply-post-apply-hook #'xenops-apply-post-apply-track-image-size-changes)

(provide 'xenops-apply)
