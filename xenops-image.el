;;; xenops-image.el --- Functions for working with elements of type 'image -*- lexical-binding: t; -*-

;;; Commentary:

;; Elements of type 'image represent (bitmap) images whose point of truth is an image file on disk
;; (as opposed to (SVG) images of typeset LaTeX fragments which may be cached on disk but for which
;; the point of truth is the LaTeX code).

;;; Code:

(defvar xenops-image-width 512)

(defvar xenops-image-directory nil
  "The directory in which Xenops should offer to save images when
pasted from the system clipboard.")

(defvar xenops-image-latex-template
  "\\includegraphics[width=400pt]{%s}"
  "LaTeX code for inclusion of a pasted image in the LaTeX
  document. This must be a string of valid LaTeX code containing
  a single %s placeholder, which will be replaced by the image
  file path. Use a double backslash here to produce a single
  backslash in the resulting LaTeX.")

(defun xenops-image-render (element)
  (let ((image (create-image (plist-get element :path)
                             'imagemagick nil :width xenops-image-width)))
    (add-text-properties (plist-get element :begin)
                         (plist-get element :end)
                         `(display ,image keymap ,xenops-rendered-element-keymap))))

(defun xenops-image-reveal (element)
  (remove-text-properties (plist-get element :begin)
                          (plist-get element :end)
                          '(display nil keymap nil)))

(defun xenops-image-increase-size (element)
  (image--change-size xenops-math-image-change-size-factor))

(defun xenops-image-decrease-size (element)
  (image--change-size (/ 1 xenops-math-image-change-size-factor)))

(defun xenops-image-post-apply-hook-function (handlers &optional beg end region-active)
  "Track image size changes so that new images are displayed with the correct size."
  ;; Hack: In some sense we want a new image to have the expected size, given any changes to image
  ;; size that have been applied to existing images. Here we track the overall image scale, paying
  ;; attention only when a user has resized all the images in the buffer, i.e. not when region is
  ;; active.
  (and beg end
       (eq beg (point-min))
       (eq end (point-max))
       (cond
        ((eq handlers '(xenops-image-increase-size))
         (setq xenops-math-image-current-scale-factor (* xenops-math-image-current-scale-factor
                                                         xenops-math-image-change-size-factor)))
        ((eq handlers '(xenops-image-decrease-size))
         (setq xenops-math-image-current-scale-factor (/ xenops-math-image-current-scale-factor
                                                         xenops-math-image-change-size-factor))))))

(add-hook 'xenops-apply-post-apply-hook #'xenops-image-post-apply-hook-function)

(defun xenops-image-parse-at-point ()
  (if (looking-at (caar (xenops-elements-get 'image :delimiters)))
      (list :type 'image
            :begin (match-beginning 0)
            :end (match-end 0)
            :path (expand-file-name (match-string 2)))))

(defun xenops-image-handle-paste ()
  (interactive)
  (xenops-image-handle-paste-macos))

(defun xenops-image-handle-paste-macos ()
  (interactive)
  ;; https://github.com/jcsalterego/pngpaste
  (when (executable-find "pngpaste")
    (let ((temp-file (make-temp-file "xenops-image-from-clipboard-"))
          (output-file))
      (let ((exit-status
             (call-process "pngpaste" nil `(:file ,temp-file) nil "-")))
        (if (= exit-status 0)
            (let ((file-name-suggestion
                   (xenops-image-suggest-file-name
                    (format "-%s.%s" (substring (sha1 (f-read-bytes temp-file)) 0 4) "png"))))
              (setq output-file
                    (read-file-name "Save image as: "
                                    (or xenops-image-directory default-directory)
                                    nil nil file-name-suggestion))
              (when (file-exists-p output-file) (error "File exists: %s" output-file))
              (copy-file temp-file output-file t))))
      (when output-file
        (save-excursion
          (insert (format xenops-image-latex-template
                          (file-relative-name output-file))))
        (xenops-image-render (xenops-apply-parse-next-element))
        t))))

(defun xenops-image-suggest-file-name (&optional suffix)
  (save-excursion
    (let ((outline-regexp "\\\\\\(sub\\)*section{\\([^}]*\\)}")
          pos headings)
      (ignore-errors (outline-back-to-heading))
      (setq pos (1+ (point-max)))
      (while (and (< (point) pos) (outline-on-heading-p))
        (setq headings
              (push (s-downcase (s-replace-regexp "[ :/]+" "-" (match-string 2)))
                    headings))
        (setq pos (point))
        (outline-up-heading 1))
      (format "%s%s"
              (s-join "--" (append (list (f-base (buffer-name))) headings))
              (or suffix "")))))

(provide 'xenops-image)

;;; xenops-image.el ends here
