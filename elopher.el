;;; elopher.el --- elisp gopher client

;;; Commentary:

;; An elisp gopher client.

;;; Code:

;;; Global constants
;;

(defconst elopher-version "1.0.0"
  "Current version of elopher.")

(defconst elopher-margin-width 6
  "Width of left-hand margin used when rendering indicies.")

(defconst elopher-start-index
  (mapconcat
   'identity
   (list "i\tfake\tfake\t1"
         "i--------------------------------------------\tfake\tfake\t1"
         "i          Elopher Gopher Client             \tfake\tfake\t1"
         (format "i              version %s\tfake\tfake\t1" elopher-version)
         "i--------------------------------------------\tfake\tfake\t1"
         "i\tfake\tfake\t1"
         "iBasic usage:\tfake\tfake\t1"
         "i\tfake\tfake\t1"
         "i - tab/shift-tab: next/prev directory entry on current page\tfake\tfake\t1"
         "i - RET/mouse-1: open directory entry under cursor\tfake\tfake\t1"
         "i - u: return to parent directory entry\tfake\tfake\t1"
         "i - g: go to a particular page\tfake\tfake\t1"
         "i - r: reload current page\tfake\tfake\t1"
         "i - d: download directory entry under cursor\tfake\tfake\t1"
         "i - w: display the raw server response for the current page\tfake\tfake\t1"
         "i\tfake\tfake\t1"
         "iPlaces to start exploring Gopherspace:\tfake\tfake\t1"
         "i\tfake\tfake\t1"
         "1Floodgap Systems Gopher Server\t\tgopher.floodgap.com\t70"
         "i\tfake\tfake\t1"
         "iAlternatively, select the following item and enter some\tfake\tfake\t1"
         "isearch terms:\tfake\tfake\t1"
         "i\tfake\tfake\t1"
         "7Veronica-2 Gopher Search Engine\t/v2/vs\tgopher.floodgap.com\t70"
         ".")
   "\r\n")
  "Source for elopher start page.")


;;; Customization group
;;

(defgroup elopher nil
  "A gopher client."
  :group 'applications)

(defface elopher-index
  '((((background dark)) :foreground "deep sky blue")
    (((background light)) :foreground "blue"))
  "Face used for index records.")

(defface elopher-text
  '((default :weight "bold")
    (((background dark)) :foreground "white"))
  "Face used for text records.")

(defface elopher-info '()
  "Face used for info records.")

(defface elopher-image
  '((((background dark)) :foreground "green")
    (t :foreground "dark green"))
  "Face used for image records.")

(defface elopher-search
  '((((background light)) :foreground "orange")
    (((background dark)) :foreground "dark orange"))
  "Face used for search records.")

(defface elopher-url
  '((((background dark)) :foreground "yellow")
    (((background light)) :foreground "dark red"))
  "Face used for url records.")

(defface elopher-binary
  '((t :foreground "magenta"))
  "Face used for binary records.")

(defface elopher-unknown
  '((t :foreground "red"))
  "Face used for unknown record types.")

(defface elopher-margin-key
  '((((background dark)) :foreground "white"))
  "Face used for margin key.")

(defface elopher-margin-brackets
  '((t :foreground "blue"))
  "Face used for brackets around margin key.")

(defcustom elopher-open-urls-with-eww nil
  "If non-nil, open URL selectors using eww.
Otherwise, use the system browser via the BROWSE-URL function."
  :type '(boolean))

;;; Model
;;

;; Address

(defun elopher-make-address (selector host port)
  (list selector host port))

(defun elopher-address-selector (address)
  (car address))

(defun elopher-address-host (address)
  (cadr address))

(defun elopher-address-port (address)
  (caddr address))

;; Node

(defun elopher-make-node (parent address getter &optional content pos)
  (list parent address getter content pos))

(defun elopher-node-parent (node)
  (elt node 0))

(defun elopher-node-address (node)
  (elt node 1))

(defun elopher-node-getter (node)
  (elt node 2))

(defun elopher-node-content (node)
  (elt node 3))

(defun elopher-node-pos (node)
  (elt node 4))

(defun elopher-set-node-content (node content)
  (setcar (nthcdr 3 node) content))

(defun elopher-set-node-pos (node pos)
  (setcar (nthcdr 4 node) pos))

(defun elopher-save-pos ()
  (when elopher-current-node
    (elopher-set-node-pos elopher-current-node (point))))

(defun elopher-restore-pos ()
  (let ((pos (elopher-node-pos elopher-current-node)))
    (if pos
        (goto-char pos)
      (goto-char (point-min)))))

;; Node graph traversal

(defvar elopher-current-node)

(defun elopher-visit-node (node &optional getter)
  (elopher-save-pos)
  (elopher-process-cleanup)
  (setq elopher-current-node node)
  (if getter
      (funcall getter)
    (funcall (elopher-node-getter node))))

(defun elopher-visit-parent-node ()
  (let ((parent-node (elopher-node-parent elopher-current-node)))
    (when parent-node
      (elopher-visit-node parent-node))))
      
(defun elopher-reload-current-node ()
  (elopher-set-node-content elopher-current-node nil)
  (elopher-visit-node elopher-current-node))

;;; Buffer preparation
;;

(defmacro elopher-with-clean-buffer (&rest args)
  "Evaluate ARGS with a clean *elopher* buffer as current."
  (list 'progn
        '(switch-to-buffer "*elopher*")
        '(elopher-mode)
        (append (list 'let '((inhibit-read-only t))
                      '(erase-buffer))
                args)))

;;; Index rendering
;;

(defun elopher-insert-index (string)
  "Insert the index corresponding to STRING into the current buffer."
  (dolist (line (split-string string "\r\n"))
    (unless (= (length line) 0)
      (elopher-insert-index-record line))))

(defun elopher-insert-margin (&optional type-name)
  "Insert index margin, optionally containing the TYPE-NAME, into the current buffer."
  (if type-name
      (progn
        (insert (format (concat "%" (number-to-string (- elopher-margin-width 1)) "s")
                        (concat
                         (propertize "[" 'face 'elopher-margin-brackets)
                         (propertize type-name 'face 'elopher-margin-key)
                         (propertize "]" 'face 'elopher-margin-brackets))))
        (insert " "))
    (insert (make-string elopher-margin-width ?\s))))

(defvar elopher-type-map
  '((?0 elopher-get-text-node "T" elopher-text)
    (?1 elopher-get-index-node "/" elopher-index)
    (?g elopher-get-image-node "im" elopher-image)
    (?p elopher-get-image-node "im" elopher-image)
    (?I elopher-get-image-node "im" elopher-image)
    (?4 elopher-get-node-download "B" elopher-binary)
    (?5 elopher-get-node-download "B" elopher-binary)
    (?9 elopher-get-node-download "B" elopher-binary)
    (?7 elopher-get-search-node "?" elopher-search))
  "Association list from types to getters, margin codes and index faces.")

(defun elopher-insert-index-record (line)
  "Insert the index record corresponding to LINE into the current buffer."
  (let* ((type (elt line 0))
         (fields (split-string (substring line 1) "\t"))
         (display-string (elt fields 0))
         (selector (elt fields 1))
         (host (elt fields 2))
         (port (elt fields 3))
         (address (elopher-make-address selector host port))
         (type-map-entry (alist-get type elopher-type-map)))
    (if type-map-entry
        (let ((getter (car type-map-entry))
              (margin-code (cadr type-map-entry))
              (face (caddr type-map-entry)))
          (elopher-insert-margin margin-code)
          (insert-text-button display-string
                              'face face
                              'elopher-node (elopher-make-node elopher-current-node
                                                               address
                                                               getter)
                              'action #'elopher-click-link
                              'follow-link t
                              'help-echo (format "mouse-1, RET: open %s on %s port %s"
                                                 selector host port)))
      (pcase type
        (?i (elopher-insert-margin) ; Information 
            (insert (propertize display-string
                                'face 'elopher-info)))
        (?h (elopher-insert-margin "W") ; Web link
            (let ((url (elt (split-string selector "URL:") 1)))
              (insert-text-button display-string
                                  'face 'elopher-url
                                  'elopher-url url
                                  'action #'elopher-click-url
                                  'follow-link t
                                  'help-echo (format "mouse-1, RET: open url %s" url))))
        (?.) ; Occurs at end of index, can safely ignore.
        (tp (elopher-insert-margin (concat (char-to-string tp) "?"))
            (insert (propertize display-string
                                'face elopher-unknown-face)))))
    (insert "\n")))


;;; Selector retrieval (all kinds)
;;

(defun elopher-process-cleanup ()
  "Immediately shut down any extant elopher process."
  (let ((p (get-process "elopher-process")))
    (if p (delete-process p))))

(defvar elopher-selector-string)

(defun elopher-get-selector (address after)
  "Retrieve selector specified by ADDRESS, then execute AFTER.
The result is stored as a string in the variable elopher-selector-string."
  (setq elopher-selector-string "")
  (make-network-process
   :name "elopher-process"
   :host (elopher-address-host address)
   :service (elopher-address-port address)
   :filter (lambda (proc string)
             (setq elopher-selector-string (concat elopher-selector-string string)))
   :sentinel after)
  (process-send-string "elopher-process"
                       (concat (elopher-address-selector address) "\n")))

;; Index retrieval

(defun elopher-get-index-node ()
  (let ((content (elopher-node-content elopher-current-node))
        (address (elopher-node-address elopher-current-node)))
    (if content
        (progn
          (elopher-with-clean-buffer
           (insert content))
          (elopher-restore-pos))
      (if address
          (progn
            (elopher-with-clean-buffer
             (insert "LOADING DIRECTORY..."))
            (elopher-get-selector address
                                  (lambda (proc event)
                                    (unless (string-prefix-p "deleted" event)
                                      (elopher-with-clean-buffer
                                       (elopher-insert-index elopher-selector-string))
                                      (elopher-restore-pos)
                                      (elopher-set-node-content elopher-current-node
                                                                (buffer-string))))))
        (progn
          (elopher-with-clean-buffer
           (elopher-insert-index elopher-start-index))
          (elopher-restore-pos)
          (elopher-set-node-content elopher-current-node
                                    (buffer-string)))))))

;; Text retrieval

(defconst elopher-url-regex "\\(https?\\|gopher\\)://\\([a-zA-Z0-9.\-]+\\)\\(?3::[0-9]+\\)?\\(?4:/[^ \r\n\t(),]*\\)"
  "Regexp used to locate and buttinofy URLs in text files loaded by elopher.")

(defun elopher-buttonify-urls (string)
  "Turn substrings which look like urls in STRING into clickable buttons."
  (with-temp-buffer
    (insert string)
    (goto-char (point-min))
    (while (re-search-forward elopher-url-regex nil t)
      (let ((url (match-string 0))
            (protocol (downcase (match-string 1))))
        (if (string= protocol "gopher")
            (let* ((host (match-string 2))
                   (port 70)
                   (type-and-selector (match-string 4))
                   (type (if (> (length type-and-selector) 1)
                             (elt type-and-selector 1)
                           ?1))
                   (selector (if (> (length type-and-selector) 1)
                                 (substring type-and-selector 2)
                               ""))
                   (address (elopher-make-address selector host port))
                   (getter (car (alist-get type elopher-type-map))))
              (make-text-button (match-beginning 0)
                                (match-end 0)
                                'elopher-node (elopher-make-node elopher-current-node
                                                                 address
                                                                 getter)
                                'action #'elopher-click-link
                                'follow-link t
                                'help-echo (format "mouse-1, RET: open %s on %s port %s"
                                                   selector host port)))
          (make-text-button (match-beginning 0)
                            (match-end 0)
                            'elopher-url url
                            'action #'elopher-click-url
                            'follow-link t
                            'help-echo (format "mouse-1, RET: open url %s" url)))))
    (buffer-string)))

(defun elopher-process-text (string)
  (let* ((chopped-str (replace-regexp-in-string "\r\n\.\r\n$" "\r\n" string))
         (cleaned-str (replace-regexp-in-string "\r" "" chopped-str)))
    (elopher-buttonify-urls cleaned-str)))

(defun elopher-get-text-node ()
  (let ((content (elopher-node-content elopher-current-node))
        (address (elopher-node-address elopher-current-node)))
    (if content
        (progn
          (elopher-with-clean-buffer
           (insert content))
          (elopher-restore-pos))
      (progn
        (elopher-with-clean-buffer
         (insert "LOADING TEXT..."))
        (elopher-get-selector address
                              (lambda (proc event)
                                (unless (string-prefix-p "deleted" event)
                                  (elopher-with-clean-buffer
                                   (insert (elopher-process-text elopher-selector-string)))
                                  (elopher-restore-pos)
                                  (elopher-set-node-content elopher-current-node
                                                            (buffer-string)))))))))

;; Image retrieval

(defun elopher-get-image-node ()
  (let ((content (elopher-node-content elopher-current-node))
        (address (elopher-node-address elopher-current-node)))
    (if content
        (progn
          (elopher-with-clean-buffer
           (insert-image content))
          (setq cursor-type nil)
          (elopher-restore-pos))
      (progn
        (elopher-with-clean-buffer
         (insert "LOADING IMAGE..."))
        (elopher-get-selector address
                              (lambda (proc event)
                                (unless (string-prefix-p "deleted" event)
                                  (let ((image (create-image
                                                (string-as-unibyte elopher-selector-string)
                                                nil t)))
                                    (elopher-with-clean-buffer
                                     (insert-image image))
                                    (setq cursor-type nil)
                                    (elopher-restore-pos)
                                    (elopher-set-node-content elopher-current-node
                                                              image)))))))))

;; Search retrieval

(defun elopher-get-search-node ()
  (let ((content (elopher-node-content elopher-current-node))
        (address (elopher-node-address elopher-current-node))
        (aborted t))
    (if content
        (progn
          (elopher-with-clean-buffer
           (insert content))
          (elopher-restore-pos)
          (message "Displaying cached search results.  Reload to perform a new search."))
      (unwind-protect
          (let* ((query-string (read-string "Query: "))
                 (query-selector (concat (elopher-address-selector address) "\t" query-string))
                 (search-address (elopher-make-address query-selector
                                                       (elopher-address-host address)
                                                       (elopher-address-port address))))
            (setq aborted nil)
            (elopher-with-clean-buffer
             (insert "LOADING RESULTS..."))
            (elopher-get-selector search-address
                                  (lambda (proc event)
                                    (unless (string-prefix-p "deleted" event)
                                      (elopher-with-clean-buffer
                                       (elopher-insert-index elopher-selector-string))
                                      (goto-char (point-min))
                                      (elopher-set-node-content elopher-current-node
                                                                (buffer-string))))))
        (if aborted
            (elopher-visit-parent-node))))))

;; Raw server response retrieval

(defun elopher-get-node-raw ()
  (let* ((content (elopher-node-content elopher-current-node))
         (address (elopher-node-address elopher-current-node)))
    (elopher-with-clean-buffer
     (insert "LOADING RAW SERVER RESPONSE..."))
    (if address
        (elopher-get-selector address
                              (lambda (proc event)
                                (unless (string-prefix-p "deleted" event)
                                  (elopher-with-clean-buffer
                                   (insert elopher-selector-string))
                                  (goto-char (point-min)))))
      (progn
        (elopher-with-clean-buffer
         (insert elopher-start-index))
        (goto-char (point-min)))))
  (message "Displaying raw server response.  Reload to return to standard view."))
 
;; File export retrieval

(defvar elopher-download-filename)

(defun elopher-get-node-download ()
  (let* ((address (elopher-node-address elopher-current-node))
         (selector (elopher-address-selector address)))
    (elopher-visit-parent-node) ; Do first in case of non-local exits.
    (let* ((filename-proposal (file-name-nondirectory selector))
           (filename (read-file-name "Save file as: "
                                     nil nil nil
                                     (if (> (length filename-proposal) 0)
                                         filename-proposal
                                       "gopher.file"))))
      (message "Downloading...")
      (setq elopher-download-filename filename)
      (elopher-get-selector address
                            (lambda (proc event)
                              (let ((coding-system-for-write 'binary))
                                (with-temp-file elopher-download-filename
                                  (insert elopher-selector-string)
                                  (message (format "Download complate, saved to file %s."
                                                   elopher-download-filename)))))))))


;;; Navigation procedures
;;

(defun elopher-next-link ()
  (interactive)
  (forward-button 1))

(defun elopher-prev-link ()
  (interactive)
  (backward-button 1))

(defun elopher-click-link (button)
  (let ((node (button-get button 'elopher-node)))
    (elopher-visit-node node)))

(defun elopher-click-url (button)
  (let ((url (button-get button 'elopher-url)))
    (if elopher-open-urls-with-eww
        (browse-web url)
      (browse-url url))))

(defun elopher-follow-closest-link ()
  (interactive)
  (push-button))

(defun elopher-go ()
  "Go to a particular gopher site."
  (interactive)
  (let* (
         (hostname (read-string "Gopher host: "))
         (selector (read-string "Selector (default none): " nil nil ""))
         (port (read-string "Port (default 70): " nil nil 70))
         (address (list selector hostname port)))
    (elopher-visit-node
     (elopher-make-node elopher-current-node
                        address
                        #'elopher-get-index-node))))

(defun  elopher-reload ()
  "Reload current page."
  (interactive)
  (elopher-reload-current-node))

(defun elopher-view-raw ()
  "View current page as plain text."
  (interactive)
  (elopher-visit-node elopher-current-node
                      #'elopher-get-node-raw))

(defun elopher-back ()
  "Go to previous site."
  (interactive)
  (if (elopher-node-parent elopher-current-node)
      (elopher-visit-parent-node)
    (message "No previous site.")))

(defun elopher-download ()
  "Download the link at point."
  (interactive)
  (let ((button (button-at (point))))
    (if button
        (let ((node (button-get button 'elopher-node)))
          (if node
              (elopher-visit-node (button-get button 'elopher-node)
                                  #'elopher-get-node-download)
            (message "Can only download gopher links, not general URLs.")))
      (message "No link selected."))))

;;; Mode and keymap
;;

(defvar elopher-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "<tab>") 'elopher-next-link)
    (define-key map (kbd "<S-tab>") 'elopher-prev-link)
    (define-key map (kbd "u") 'elopher-back)
    (define-key map (kbd "g") 'elopher-go)
    (define-key map (kbd "r") 'elopher-reload)
    (define-key map (kbd "w") 'elopher-view-raw)
    (define-key map (kbd "d") 'elopher-download)
    (when (fboundp 'evil-define-key)
      (evil-define-key 'normal map
        (kbd "C-]") 'elopher-follow-closest-link
        (kbd "C-t") 'elopher-back
        (kbd "u") 'elopher-back
        (kbd "g") 'elopher-go
        (kbd "r") 'elopher-reload
        (kbd "w") 'elopher-view-raw
        (kbd "d") 'elopher-download))
    map)
  "Keymap for gopher client.")

(define-derived-mode elopher-mode special-mode "elopher"
  "Major mode for elopher, an elisp gopher client.")


;;; Main start procedure
;;

(defun elopher ()
  "Start elopher with default landing page."
  (interactive)
  (setq elopher-current-node nil)
  (let ((start-node (elopher-make-node nil nil #'elopher-get-index-node)))
    (elopher-visit-node start-node))
  "Started Elopher.") ; Otherwise (elopher) evaluates to start page string.

;;; elopher.el ends here
