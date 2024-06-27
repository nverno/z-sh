;;; z-sh.el --- Jump around with z.sh integration -*- lexical-binding: t; -*-

;; Author: Noah Peart <noah.v.peart@gmail.com>
;; URL: https://github.com/nverno/z-sh
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1"))
;; Created: 27 June 2024
;; Keywords: shell, convenience

;; This file is not part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth
;; Floor, Boston, MA 02110-1301, USA.

;;; Commentary:
;;
;; Add `z-sh-directory-tracker' to `comint-input-filter-functions' in your
;; `shell-mode-hook' hook to sync with comint's directory tracking after z
;; jumps.
;;
;; To track dired directories in the z database, add `z-sh-add-directory' to
;; `dired-mode-hook'.
;;  
;;; Code:

(eval-when-compile (require 'dash))
(require 'comint)
(require 'xterm-color)

(defgroup z-sh nil
  "Z.sh integration"
  :group 'languages
  :prefix "z-sh")

(defcustom z-sh-data (or (getenv "_Z_DATA") (expand-file-name "~/.cache/.z"))
  "Location of z.sh data."
  :type 'string)

(defcustom z-sh-program "z.sh"
  "Location of z.sh."
  :type 'string)

(defvar z-sh--dir
  (cond (load-in-progress load-file-name)
        ((and (boundp 'byte-compile-current-file)
              byte-compile-current-file)
         byte-compile-current-file)
        (t (buffer-file-name))))

(defun z-sh--comint-redirect-to-string (command)
  (let* ((proc (get-buffer-process (current-buffer)))
         (buf (generate-new-buffer "*z-sh*" t))
         (comint-redirect-filter-functions '(xterm-color-filter)))
    (comint-redirect-send-command command buf nil t)
    (with-current-buffer (process-buffer proc)
      (while (and (null comint-redirect-completed) ;ignore output
                  (accept-process-output proc 1))))
    (comint-redirect-cleanup)
    (with-current-buffer buf
      ;; drop the last line from 2-line prompt
      (goto-char (point-max))
      (forward-line -1)
      (end-of-line)
      (prog1 (string-chop-newline
              (buffer-substring-no-properties
               (point-min)
               (max 1 (1- (line-beginning-position)))))
        (and (buffer-name buf)
             (kill-buffer buf))))))

;;; Directory tracking after z jumps
(defun z-sh--directory-tracker ()
  (advice-remove #'shell-directory-tracker #'ignore)
  (let ((dir (z-sh--comint-redirect-to-string "command dirs")))
    (when (file-exists-p dir)
      (shell-directory-tracker dir)
      (setq default-directory (file-name-as-directory dir)))))

(defun z-sh-directory-tracker (str)
  (when (string-match-p "^\\s-*z\\b" str)
    (advice-add #'shell-directory-tracker :override #'ignore)
    (run-with-timer 0.4 nil #'z-sh--directory-tracker)))


;;; Dired
(defun z-sh-add-directory ()
  "Add dired directory to z.sh database."
  (when (file-exists-p z-sh-program)
    (start-process-shell-command
     "bash" nil
     (concat
      "env _Z_DATA=" z-sh-data " "
      (format "bash -c '. %s; cd %s && _z --add \"$(pwd)\"'"
              z-sh-program (expand-file-name default-directory))))))

;;; TODO(6/27/24): optional sort by frecency/recent
(defun z-sh--directories (&optional frecency)
  "Read frecent directories from z.sh database.
If FRECENCY is non-nil, limit to those with a score of at least FRECENCY."
  (let ((data (or (getenv "_Z_DATA") z-sh-data))
        (bin (expand-file-name "bin/frecent.awk" z-sh--dir)))
    (when (file-exists-p data)
      (process-lines
       shell-file-name
       shell-command-switch
       (concat "gawk -F'|'" (if frecency
                                (format " -v frecency=\"%s\"" frecency)
                              "")
               " -f " bin " " data)))))

;;;###autoload
(defun z-sh-dired-jump (dir other-window)
  "Dired jump to frecent directory."
  (interactive
   (list (--when-let (z-sh--directories)
           (completing-read "Frecent Directory: "
             (mapcar #'abbreviate-file-name it)))
         current-prefix-arg))
  (dired-jump current-prefix-arg dir))


(provide 'z-sh)
;; Local Variables:
;; coding: utf-8
;; indent-tabs-mode: nil
;; End:
;;; z-sh.el ends here
