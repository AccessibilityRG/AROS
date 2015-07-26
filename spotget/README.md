spotget
=======


*spotget* is a small tool that retrieves XML data from
[Findmespot shared page XML feed](http://faq.findmespot.com/index.php?action=showEntry&amp;data=69)
and stores all coordinates to ttget table using `HY::Geo::ttgetdb`.

*spotget* is configured using `messages.ini` common for all AROS scripts. Following directives are relevant for spotget:

* section "database" (`dbi`, `username`, `password`)
* section "spotget" (`url`, `browser_timeout`, `browser_id`)
		
*spotget* code is documented in POD way. There are also comments in the code.

