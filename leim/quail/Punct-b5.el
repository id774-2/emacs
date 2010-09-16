;; Quail package `chinese-punct-b5' -*- coding:chinese-big5-unix; byte-compile-disable-print-circle:t; -*-
;;   Generated by the command `titdic-convert'
;;	Date: Thu Sep 16 11:45:55 2010
;;	Original TIT dictionary file: Punct-b5.tit

;;; Comment:

;; Byte-compile this file again after any modification.

;;; Start of the header of original TIT dictionary.

;; # HANZI input table for cxterm
;; # Generated from Punct-b5.cit by cit2tit
;; # To be used by cxterm, convert me to .cit format first
;; # .cit version 1
;; ENCODE:	BIG5
;; MULTICHOICE:	YES
;; PROMPT:	中文輸入【標點符號】
;; #
;; COMMENT Copyright 1991 by Yongguang Zhang.	(ygz@cs.purdue.edu)
;; COMMENT Permission to use/modify/copy for any purpose is hereby granted.
;; COMMENT Absolutely no fee and no warranties.
;; COMMENT
;; COMMENT use <CTRL-f> to move to the right
;; COMMENT use <CTRL-b> to move to the left
;; COMMENT Modify by Wei-Chung Hwang, OCT 15, 1992.
;; # define keys
;; VALIDINPUTKEY:	!"\043$%&'()*+,-./0123456789:;<=>?@[\134]^_`abcdefghijkl
;; VALIDINPUTKEY:	mnopqrstuvwxyz{|}~
;; SELECTKEY:	1\040
;; SELECTKEY:	2
;; SELECTKEY:	3
;; SELECTKEY:	4
;; SELECTKEY:	5
;; SELECTKEY:	6
;; SELECTKEY:	7
;; SELECTKEY:	8
;; SELECTKEY:	9
;; SELECTKEY:	0
;; BACKSPACE:	\010\177
;; DELETEALL:	\015\025
;; MOVERIGHT:	\006
;; MOVELEFT:	\002
;; REPEATKEY:	\020\022
;; # the following line must not be removed
;; BEGINDICTIONARY

;;; End of the header of original TIT dictionary.

;;; Code:

(require 'quail)

(quail-define-package "chinese-punct-b5" "Chinese-BIG5" "標B"
 t
"中文輸入【標點符號】

 Copyright 1991 by Yongguang Zhang.	(ygz@cs.purdue.edu)
 Permission to use/modify/copy for any purpose is hereby granted.
 Absolutely no fee and no warranties.

 use <CTRL-f> to move to the right
 use <CTRL-b> to move to the left
 Modify by Wei-Chung Hwang, OCT 15, 1992.

Input method for Chinese punctuations and symbols of Big5
(`chinese-big5-1' and `chinese-big5-2').
"
 '(("\C-?" . quail-delete-last-char)
   
   
   )
 nil nil nil nil)

(quail-define-rules
("!" "！﹗")
("\"" "“”〝〞〃")
("#" "＃﹟")
("$" "¥﹩¢£")
("%" "％")
("&" "﹠＆")
("'" "‘’‵′")
("(" "（〔﹙︵︹「『﹂﹄")
(")" "）〕﹚︶︺」』﹁﹃")
("*" "﹡×ΠΛ∩")
("+" "＋﹢±Σ﹀∪")
("," "，﹐、､")
("-" "－﹣﹣–‾─∼")
("." "。．•﹒·…‥∵∴°☉")
("/" "／／÷√＼＼")
("0" "０�怗痑遉瞽�")
("1" "１�瓊礿蛁飾璽�")
("2" "２�耀峉堞滯罌�")
("3" "３�籟洷晬誥�")
("4" "４�ゞ苺琡慰�")
("5" "５�ラ悈菺耦�")
("6" "６���猀隃麩�")
("7" "７�氿茛摃縈�")
("8" "８�呁啥煍壕�")
("9" "９�芄掁腡蕾�")
(":" "：︰﹕")
(";" "；﹔")
("<" "〈﹤《︽︿≦")
("=" "＝﹦≠≒≡")
(">" "〉﹥》︾﹀≧")
("?" "？﹖")
("@" "＠☉")
("[" "﹝【︻")
("\\" "＼＼／／")
("]" "﹞】︼")
("^" "︿")
("_" "╴﹏")
("`" "‘’‵′")
("a" "ａ")
("b" "ｂ")
("c" "ｃ")
("d" "ｄ")
("e" "ｅ")
("f" "ｆ")
("g" "ｇ")
("h" "ｈ")
("i" "ｉ")
("j" "ｊ")
("k" "ｋ")
("l" "ｌ")
("m" "ｍ")
("n" "ｎ")
("o" "ｏ")
("p" "ｐ")
("q" "ｑ")
("r" "ｒ")
("s" "ｓ")
("t" "ｔ")
("u" "ｕ")
("v" "ｖ")
("w" "ｗ")
("x" "ｘ")
("y" "ｙ")
("z" "ｚ")
("A" "Ａ")
("B" "Ｂ")
("C" "Ｃ")
("D" "Ｄ")
("E" "Ｅ")
("F" "Ｆ")
("G" "Ｇ")
("H" "Ｈ")
("I" "Ｉ")
("J" "Ｊ")
("K" "Ｋ")
("L" "Ｌ")
("M" "Ｍ")
("N" "Ｎ")
("O" "Ｏ")
("P" "Ｐ")
("Q" "Ｑ")
("R" "Ｒ")
("S" "Ｓ")
("T" "Ｔ")
("U" "Ｕ")
("V" "Ｖ")
("W" "Ｗ")
("X" "Ｘ")
("Y" "Ｙ")
("Z" "Ｚ")
("graph" "▁▂▃▄▅▆▇█▏▎▍▌▋▊▉┼┴┬┤├▔─│▕┌┐└┘╭╮╰╯═╞╪╡◢◣◥◤╱╲╳")
("logo" "＊※§〃○●△▲◎☆★◇◆□■▽▼㊣℅‾￣＿ˍ﹉﹊﹍﹎﹋﹌")
("math" "＋－×÷±√＜＞＝≦≧≠∞≒≡﹢﹣﹤﹥﹦∼∩∪⊥∠∟⊿㏒㏑∫∮∵∴")
("symbol" "♂♀♁☉↑↓←→↖↗↙↘∥∣／＼／＼")
("unit" "＄¥〒¢£％％＠㎜㎝㎞㏎㎡㎎㎏㏄°兙兛兞兝兡兣嗧瓩糎")
("{" "﹛｛︷")
("|" "｜∣︳│∥")
("}" "﹜｝︸")
("~" "﹏∼∞")
)
