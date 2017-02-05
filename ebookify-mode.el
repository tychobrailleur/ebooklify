;;; ebookify-mode.el --- Creates ebooks              -*- lexical-binding: t; -*-

;; Copyright (C) 2017  Sébastien Le Callonnec

;; Author: Sébastien Le Callonnec <sebastien@weblogism.com>
;; Version: 0.1.0
;; Keywords:
;; Require-Packages: ((mongo-el "0.0.0") (s "1.11.0")

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Create an eBook from a collection of documents in a known format.

;;; Code:
(require 's)
(require 'ebookify-doc)
(require 'ebookify-mongo)

(defgroup ebookify nil
  "ebookify parameters"
  :group 'applications)

(defcustom ebookify-document-backend
  "mongo"
  "Backend storing the documents to be added to the ebook."
  :type 'string
  :group 'ebookify)

(defcustom ebookify-output-directory
  "/tmp"
  "Directory where output files are created."
  :type 'directory
  :group 'ebookify)

(defcustom ebookify-output-document-format
  'mobi
  "eBook format."
  :type '(choice (const :tag "epub" epub)
                 (const :tag "epub3" epub3)
                 (const :tag "mobi" mobi))
  :group 'ebookify)

(defcustom ebookify-pandoc-executable
  "/usr/bin/pandoc"
  "Path to Pandoc executable."
  :type '(file :must-match t)
  :group 'ebookify)

(defcustom ebookify-document-format
  "html"
  "Original format of the document."
  :type 'string
  :group 'ebookify)

(defvar ebookify--template-directory nil)
(setq ebookify--template-directory
      (when load-file-name
        (expand-file-name "templates" (file-name-directory load-file-name))))

(defun ebookify--docfile (document extension)
  (expand-file-name (concat (document-num document) extension) ebookify-output-directory))

(defun ebookify--store-document (document)
  (write-region (document-body document) nil (ebookify--docfile document ".html") nil nil nil t))

(defun ebookify--read-file-to-string (file-path)
  (with-temp-buffer
    (insert-file-contents file-path)
    (buffer-string)))

(defun ebookify--convert-to-tex (document)
  "Convert the document format to TeX."
  (let ((docfile (ebookify--docfile document ".html")))
    (shell-command-to-string
     (format "%s -f %s -t latex -o %s %s"
             ebookify-pandoc-executable ebookify-document-format
             (ebookify--docfile document ".tex") docfile))))

(defun ebookify--read-template (template-name)
  (let ((template-path (expand-file-name template-name ebookify--template-directory)))
    (ebookify--read-file-to-string template-path)))

(defun ebookify--expand-section-template (document template)
  (s-replace ":body:" (ebookify--read-file-to-string (ebookify--docfile document ".tex"))
             (s-replace ":title:" (document-title document) template)))

(defun ebookify--expand-main-template (title author sections template)
  (s-replace ":sections:" sections
             (s-replace ":author:" author
                        (s-replace ":title:" title template))))


(defun ebookify--build-source (title author documents)
  (let ((main-template (ebookify--read-template "main.txt"))
        (section-template (ebookify--read-template "section.txt"))
        (sections nil))
    (setq sections (mapconcat
                    (lambda (doc)
                      (ebookify--expand-section-template doc section-template)) documents ""))
    (write-region
     (ebookify--expand-main-template title author sections main-template) nil
     (expand-file-name "main.tex" ebookify-output-directory) nil nil nil t)))

(defun ebookify--run-tex4ebook (ebook-format)
  (shell-command-to-string (format "cd %s && tex4ebook main.tex -f %s" ebookify-output-directory ebook-format)))

(defun ebookify--get-documents-from-backend (ids)
  ;;  (require (intern (concat "ebookify-"  ebookify-document-backend)))
  (funcall (intern (format "ebookify-%s--fetch-document" ebookify-document-backend)) ids))

(defun ebookify-create-ebook (title author doc-ids)
  "Create an eBook entitled TITLE by AUTHOR with docs DOC-IDS.

DOC-IDS is a comma-separated list of unique identifiers
identifying each document to include in the eBook."
  (interactive "sTitle: \nsAuthor: \nsList of IDs: ")
  (let* ((ids (mapcar #'s-trim (split-string doc-ids ",")))
         (docs (ebookify--get-documents-from-backend ids)))
    (mapc #'ebookify--store-document docs)
    (mapc #'ebookify--convert-to-tex docs)
    (ebookify--build-source title author docs)
    (ebookify--run-tex4ebook ebookify-output-document-format)))

(provide 'ebookify-mode)
;;; ebookify-mode.el ends here
