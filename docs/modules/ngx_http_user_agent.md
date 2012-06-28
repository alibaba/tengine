# Name #

**ngx\_http\_user\_agent\_module**

add a directive to an analyse user_agent string

this module is bult by default in tengine, it should not be enabled with the --without-http_user_agent_module configuration parameter.

# Examples #

	http {
		user_agent $ngx_browser {
			default						unkown;


			greedy						Firefox;

			Chrome	   18.0+			chrome18;
			Chrome     17.0~17.9999		chrome17;
			Chrome     5.0-				chrome_low;
		}
	}

# Directives #

## user_agent ##

Syntax: **$variable_name** you can use this variable like other nginx variables in your configuration file.

this block contains three parts, **default**, **greedy** and **analysis iteams**.

* **default**:
 - *syntax*: **default   value**
 - note: the variable defined will return thie value if an user_agent string is not in analysis iteams.

 * **greedy**:
  - *syntax*: **greedy   keyword**
  - note: set the keyword is greedy, if keyword is greedy, it should match continue, end with a keyword isn\'t greedy.
  - e.g.: "Mozilla/5.0 (Windows NT 5.1) AppleWebKit/535.1 (KHTML, like Gecko) Chrome/13.0.782.112 Safari/535.1",this user_agent string will return Chrome13,if configuration file like this:
	greedy					Safari;
	Chrome	13.0~13.9999	chrome13;

* **analysis iateams**:
 - *syntax*: **keyword version value**
   - *keyword*: this is the word we analysised from user_agent string.
   - *version*: the version of keyword.
     - version\+:greater or equal should be matched;
	 - version\-:less or equal shoul be matched;
	 - version:equal shold be matched;
	 - version1~version2:matched in [version1,version2];
   - *value*:if this iteam has been matched,the variable defined will return this value.
