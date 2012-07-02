# Name #

**ngx\_http\_user\_agent\_module**

This module can analyse the header of User-Agent.

This module is enabled by default. It can be disabled with the --without-http_user_agent_module configuration parameter.

# Examples #

	http {
		user_agent $ngx_browser {
			default                     unknown;


			greedy                      Firefox;

			Chrome      18.0+           chrome18;
			Chrome      17.0~17.9999    chrome17;
			Chrome      5.0-            chrome_low;
		}
	}

# Directives #

## user_agent ##

Syntax: **user_agent** $variable_name   
Default: none   
Context: http   
Set a variable whose value depends on the value of user_agent string.This block contains three parts, **default**, **greedy** and **analysis items**.

### default:         
 *Syntax*: **default**   value           
 *Default*: none           
 *Context*: user_agent block  
 The default variable value if the user_agent string can't match any of the item.     

### greedy:   
 *Syntax*: **greedy   keyword**   
 *Default*: none  
 *Context*: user_agent block  
 If the keyword is greedy, it will continue to scan the user-agent string until it can find other item which is not greedy. If it can't find any other item, this keyword will be returned at last.    
e.g.: "Mozilla/5.0 (Windows NT 5.1) AppleWebKit/535.1 (KHTML, like Gecko) Chrome/13.0.782.112 Safari/535.1",this user_agent string will return Chrome13,if configuration file like this:    

    greedy                  Safari;     
    Chrome  13.0~13.9999    chrome13;   

### analysis items:     
 *Syntax*: **keyword version value**    
 *Default*: none    
 *Context*: user_agent block   

* *keyword*: This is the word we want to match from the user_agent string.    
* *version*: the version of keyword.  
       - version\+:greater or equal should be matched;    
	   - version\-:less or equal should be matched;   
	   - version:equal should be matched;     
	   - version1~version2:matched in [version1,version2];    
* *value*:If this item is matched, the value will be filled to the defined variable.  
