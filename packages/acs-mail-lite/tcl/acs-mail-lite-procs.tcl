ad_library {

    Provides a simple API for reliably sending email.
    
    @author Eric Lorenzo (eric@openforce.net)
    @creation-date 22 March 2002
    @cvs-id $Id$

}

package require mime 1.4
package require smtp 1.4
package require base64 2.3.1
namespace eval acs_mail_lite {

    #---------------------------------------
    ad_proc -public with_finally {
	-code:required
	-finally:required
    } {
	Execute CODE, then execute cleanup code FINALLY.
	If CODE completes normally, its value is returned after
	executing FINALLY.
	If CODE exits non-locally (as with error or return), FINALLY
	is executed anyway.

	@option code Code to be executed that could throw and error
	@option finally Cleanup code to be executed even if an error occurs
    } {
	global errorInfo errorCode

	# Execute CODE.
	set return_code [catch {uplevel $code} string]
	set s_errorInfo $errorInfo
	set s_errorCode $errorCode

	# As promised, always execute FINALLY.  If FINALLY throws an
	# error, Tcl will propagate it the usual way.  If FINALLY contains
	# stuff like break or continue, the result is undefined.
	uplevel $finally

	switch $return_code {
	    0 {
		# CODE executed without a non-local exit -- return what it
		# evaluated to.
		return $string
	    }
	    1 {
		# Error
		return -code error -errorinfo $s_errorInfo -errorcode $s_errorCode $string
	    }
	    2 {
		# Return from the caller.
		return -code return $string
	    }
	    3 {
		# break
		return -code break
	    }
	    4 {
		# continue
		return -code continue
	    }
	    default {
		return -code $return_code $string
	    }
	}
    }

    #---------------------------------------
    ad_proc -public get_package_id {} {
	@returns package_id of this package
    } {
        return [apm_package_id_from_key acs-mail-lite]
    }
    
    #---------------------------------------
    ad_proc -public get_parameter {
        -name:required
        {-default ""}
    } {
	Returns an apm-parameter value of this package
	@option name parameter name
	@option default default parameter value
	@returns apm-parameter value of this package
    } {
        return [parameter::get -package_id [get_package_id] -parameter $name -default $default]
    }
    
    #---------------------------------------
    ad_proc -public address_domain {} {
	@returns domain address to which bounces are directed to
    } {
        set domain [get_parameter -name "BounceDomain"]
        if { [empty_string_p $domain] } {
	    regsub {http://} [ns_config ns/server/[ns_info server]/module/nssock hostname] {} domain
	}
	return $domain
    }
    
    #---------------------------------------
    ad_proc -private bounce_sendmail {} {
	@returns path to the sendmail executable
    } {
	return [get_parameter -name "SendmailBin"]
    }
    
    #---------------------------------------
    ad_proc -private bounce_prefix {} {
	@returns bounce prefix for x-envelope-from
    } {
        return [get_parameter -name "EnvelopePrefix"]
    }
    
    #---------------------------------------
    ad_proc -private mail_dir {} {
	@returns incoming mail directory to be scanned for bounces
    } {
        return [get_parameter -name "BounceMailDir"]
    }
    
    #---------------------------------------
    ad_proc -public parse_email_address {
	-email:required
    } {
	Extracts the email address out of a mail address (like Joe User <joe@user.com>)
	@option email mail address to be parsed
	@returns only the email address part of the mail address
    } {
        if {![regexp {<([^>]*)>} $email all clean_email]} {
            return $email
        } else {
            return $clean_email
        }
    }

    #---------------------------------------
    ad_proc -public bouncing_email_p {
	-email:required
    } {
	Checks if email address is bouncing mail
	@option email email address to be checked for bouncing
	@returns boolean 1 if bouncing 0 if ok.
    } {
	return [db_string bouncing_p {} -default 0]
    }

    #---------------------------------------
    ad_proc -public bouncing_user_p {
	-user_id:required
    } {
	Checks if email address of user is bouncing mail
	@option user_id user to be checked for bouncing
	@returns boolean 1 if bouncing 0 if ok.
    } {
	return [db_string bouncing_p {} -default 0]
    }

    #---------------------------------------
    ad_proc -private log_mail_sending {
	-user_id:required
    } {
	Logs mail sending time for user
	@option user_id user for whom email sending should be logged
    } {
	db_dml record_mail_sent {}
	if {![db_resultrows]} {
	    db_dml insert_log_entry {}
	}
    }

    #---------------------------------------
    ad_proc -public bounce_address {
        -user_id:required
	-package_id:required
	-message_id:required
    } {
	Composes a bounce address
	@option user_id user_id of the mail recipient
	@option package_id package_id of the mail sending package
	        (needed to call package-specific code to deal with bounces)
	@option message_id message-id of the mail
	@returns bounce address
    } {
	return "[bounce_prefix]-$user_id-[ns_sha1 $message_id]-$package_id@[address_domain]"
    }
    
    #---------------------------------------
    ad_proc -public parse_bounce_address {
        -bounce_address:required
    } {
        This takes a reply address, checks it for consistency,
	and returns a list of user_id, package_id and bounce_signature found
	@option bounce_address bounce address to be checked
	@returns tcl-list of user_id package_id bounce_signature
    } {
        set regexp_str "\[[bounce_prefix]\]-(\[0-9\]+)-(\[^-\]+)-(\[0-9\]+)\@"
        if {![regexp $regexp_str $bounce_address all user_id signature package_id]} {
	    ns_log Notice "acs-mail-lite: bounce address not found for $bounce_address"
            return ""
        }
    	return [list $user_id $package_id $signature]
    }
    
    #---------------------------------------
    ad_proc -public generate_message_id {
    } {
        Generate an id suitable as a Message-Id: header for an email.
	@returns valid message-id for mail header
    } {
        # The combination of high resolution time and random
        # value should be pretty unique.

        return "<[clock clicks].[ns_time].oacs@[address_domain]>"
    }

    #---------------------------------------
    ad_proc -public valid_signature {
	-signature:required
	-message_id:required
    } {
        Validates if provided signature matches message_id
	@option signature signature to be checked
	@option msg message-id that the signature should be checked against
	@returns boolean 0 or 1
    } {
	if {![regexp "(<\[\-0-9\]+\\.\[0-9\]+\\.oacs@[address_domain]>)" $message_id match id] || ![string equal $signature [ns_sha1 $id]]} {
	    # either couldn't find message-id or signature doesn't match
	    return 0
	}
	return 1
    }

    #---------------------------------------
    ad_proc -private load_mails {
        -queue_dir:required
    } {
        Scans for incoming email. You need

        An incoming email has to comply to the following syntax rule:
        [<SitePrefix>][-]<ReplyPrefix>-Whatever@<BounceDomain>

        [] = optional
        <> = Package Parameters

        If no SitePrefix is set we assume that there is only one OpenACS installation. Otherwise
        only messages are dealt with which contain a SitePrefix.

        ReplyPrefixes are provided by packages that implement the callback acs_mail_lite::incoming_email
        and provide a package parameter called ReplyPrefix. Only implementations are considered where the
        implementation name is equal to the package key of the package.

        Also we only deal with messages that contain a valid and registered ReplyPrefix.
        These prefixes are automatically set in the acs_mail_lite_prefixes table.

        @author Nima Mazloumi (nima.mazloumi@gmx.de)
        @creation-date 2005-07-15

        @option queue_dir The location of the qmail mail (BounceMailDir) queue in the file-system i.e. /home/service0/mail.

        @see acs_mail_lite::incoming_email
        @see acs_mail_lite::parse_email
    } {
       
        # get list of all incoming mail
        if {[catch {
            set messages [glob "$queue_dir/new/*"]
        } errmsg]} {
            if {[string match "no files matched glob pattern*"  $errmsg ]} {
                ns_log Debug "load_mails: queue dir = $queue_dir/new/*, no messages"
            } else {
                ns_log Error "load_mails: queue dir = $queue_dir/new/ error $errmsg"
            }
            return [list]
        }
	
        # loop over every incoming mail
	foreach msg $messages {
	    ns_log Debug "load_mails: opening $msg"
	    array set email {}
	    
	    parse_email -file $msg -array email
 	    set email(to) [parse_email_address -email $email(to)]
 	    set email(from) [parse_email_address -email $email(from)]
	    ns_log Debug "load_mails: message from $email(from) to $email(to)"
           
	    set process_p 1
	    
	    #check if we have several sites. In this case a site prefix is set
	    set site_prefix [get_parameter -name SitePrefix -default ""]
	    set package_prefix ""
	    
	    if {![empty_string_p $site_prefix]} {
		regexp "($site_prefix)-(\[^-\]*)\?-(\[^@\]+)\@" $email(to) all site_prefix package_prefix rest
	        #we only process the email if both a site and package prefix was found
	        if {[empty_string_p $site_prefix] || [empty_string_p $package_prefix]} {
		    set process_p 0
		}
		#no site prefix is set, so this is the only site
	    } else {
		regexp "(\[^-\]*)-(\[^@\]+)\@" $email(to) all package_prefix rest
		#we only process the email if a package prefix was found
		if {[empty_string_p $package_prefix]} {
                    set process_p 0
                }
	    }
	    if {$process_p} {
		
		#check if an implementation exists for the package_prefix and call the callback
### FIXME!!!!!
###


#		if {[db_0or1row select_impl {}]} {
		    
		    #    ns_log Notice "load_mails: Prefix $prefix found. Calling callback implmentation $impl_name for package_id $package_id"
		    #    callback -impl $impl_name acs_mail_lite::incoming_email -array email -package_id $package_id

		    # We execute all callbacks now
		    callback acs_mail_lite::incoming_email -array email



#		} else {
#		    ns_log Notice "load_mails: prefix not found. Doing nothing."
#		}
		

	    } else {
		ns_log Error "load_mails: Either the SitePrefix setting was incorrect or not registered package prefix '$package_prefix'."
	    }
            #let's delete the file now
            if {[catch {ns_unlink $msg} errmsg]} {
                ns_log Error "load_mails: unable to delete queued message $msg: $errmsg"
            } else {
		ns_log Debug "load_mails: deleted $msg"
	    }
        }
    }

    #---------------------------------------
    ad_proc parse_email {
	-file:required
	-array:required
    } {
	An email is splitted into several parts: headers, bodies and files lists and all headers directly.
	
	The headers consists of a list with header names as keys and their correponding values. All keys are lower case.
	The bodies consists of a list with two elements: content-type and content.
	The files consists of a list with three elements: content-type, filename and content.
	
	The array with all the above data is upvared to the caller environment.

	Important headers are:
	
	-message-id (a unique id for the email, is different for each email except it was bounced from a mailer deamon)
	-subject
	-from
	-to
	
	Others possible headers:
	
	-date
	-received
        -references (this references the original message id if the email is a reply)
	-in-reply-to (this references the original message id if the email is a reply)
	-return-path (this is used for mailer deamons to bounce emails back like bounce-user_id-signature-package_id@service0.com)
	
	Optional application specific stuff only exist in special cases:
	
	X-Mozilla-Status
	X-Virus-Scanned
	X-Mozilla-Status2
	X-UIDL
	X-Account-Key
	X-Sasl-enc
	
	You can therefore get a value for a header either through iterating the headers list or simply by calling i.e. "set message_id $email(message-id)".
	
	Note: We assume "application/octet-stream" for all attachments and "base64" for
	as transfer encoding for all files.
	
	Note: tcllib required - mime, base64
	
	@author Nima Mazloumi (nima.mazloumi@gmx.de)
	@creation-date 2005-07-15
	
    } {
	upvar $array email

	#prepare the message
	if {[catch {set mime [mime::initialize -file $file]} errormsg]} {
	    ns_log error "Email could not be delivered for file $file"
	    set stream [open $file]
	    set content [read $stream]
	    close $stream
	    ns_log error "$content"
	    ns_unlink $file
	    return
	}
	
	#get the content type
	set content [mime::getproperty $mime content]
	
	#get all available headers
	set keys [mime::getheader $mime -names]
		
	set headers [list]

	# create both the headers array and all headers directly for the email array
	foreach header $keys {
	    set value [mime::getheader $mime $header]
	    set email([string tolower $header]) $value
	    lappend headers [list $header $value]
	}

	set email(headers) $headers
		
	#check for multipart, otherwise we only have one part
	if { [string first "multipart" $content] != -1 } {
	    set parts [mime::getproperty $mime parts]
	} else {
	    set parts [list $mime]
	}
	
	# travers the tree and extract parts into a flat list
	set all_parts [list]
	foreach part $parts {
	    if { [string equal [mime::getproperty $part content] "multipart/alternative" ] } {
		foreach child_part [mime::getproperty $part parts] {
		    lappend all_parts $child_part
		}
	    } else {
		lappend all_parts $part
	    }
	}
	
	set bodies [list]
	set files [list]
	
	#now extract all parts (bodies/files) and fill the email array
	foreach part $all_parts {
	    switch [mime::getproperty $part content] {
		"text/plain" {
		    lappend bodies [list "text/plain" [mime::getbody $part]]
		}
		"text/html" {
		    lappend bodies [list "text/html" [mime::getbody $part]]
		}
		"application/octet-stream" {
		    set content_type [mime::getproperty $part content]
		    set encoding [mime::getproperty $part encoding]
		    set body [mime::getbody $part -decode]
		    set content  $body
		    set params [mime::getproperty $part params]
		    if {[lindex $params 0] == "name"} {
			set filename [lindex $params 1]
		    } else {
			set filename ""
		    }
		    lappend files [list $content_type $encoding $filename $content]
		}
	    }
	}

	set email(bodies) $bodies
	set email(files) $files
	
	#release the message
	mime::finalize $mime -subordinates all
    }    
        
    #---------------------------------------
    ad_proc -private -deprecated load_mail_dir {
        -queue_dir:required
    } {
        Scans qmail incoming email queue for bounced mail and processes
	these bounced mails.
	
        @author ben@openforce.net
        @author dan.wickstrom@openforce.net
        @creation-date 22 Sept, 2001
	
        @option queue_dir The location of the qmail mail queue in the file-system.
    } {
        if {[catch {
	    # get list of all incoming mail
            set messages [glob "$queue_dir/new/*"]
        } errmsg]} {
            ns_log Debug "queue dir = $queue_dir/new/*, no messages"
            return [list]
        }
	
        set list_of_bounce_ids [list]
        set new_messages_p 0

	# loop over every incoming mail
        foreach msg $messages {
            ns_log Debug "opening file: $msg"
            if [catch {set f [open $msg r]}] {
                continue
            }
            set file [read $f]
            close $f
            set file [split $file "\n"]
	    
            set new_messages 1
            set end_of_headers_p 0
            set i 0
            set line [lindex $file $i]
            set headers [list]
	    
            # walk through the headers and extract each one
            while ![empty_string_p $line] {
                set next_line [lindex $file [expr $i + 1]]
                if {[regexp {^[ ]*$} $next_line match] && $i > 0} {
                    set end_of_headers_p 1
                }
                if {[regexp {^([^:]+):[ ]+(.+)$} $line match name value]} {
                    # join headers that span more than one line (e.g. Received)
                    if { ![regexp {^([^:]+):[ ]+(.+)$} $next_line match] && !$end_of_headers_p} {
			append line $next_line
			incr i
                    }
                    lappend headers [string tolower $name] $value
		    
                    if {$end_of_headers_p} {
			incr i
			break
                    }
                } else {
                    # The headers and the body are delimited by a null line as specified by RFC822
                    if {[regexp {^[ ]*$} $line match]} {
			incr i
			break
                    }
                }
                incr i
                set line [lindex $file $i]
            }
            set body "\n[join [lrange $file $i end] "\n"]"
	    
            # okay now we have a list of headers and the body, let's
            # put it into notifications stuff
            array set email_headers $headers
	    
            if [catch {set from $email_headers(from)}] {
                set from ""
            }
            if [catch {set to $email_headers(to)}] {
                set to ""
            }
	    
            set to [parse_email_address -email $to]
	    ns_log Debug "acs-mail-lite: To: $to"
            util_unlist [parse_bounce_address -bounce_address $to] user_id package_id signature
	    
            # If no user_id found or signature invalid, ignore message
            if {[empty_string_p $user_id] || ![valid_signature -signature $signature -msg $body]} {
		if {[empty_string_p $user_id]} {
		    ns_log Notice "acs-mail-lite: No user id $user_id found"
		} else {
		    ns_log Notice "acs-mail-lite: Invalid mail signature"
		}
                if {[catch {ns_unlink $msg} errmsg]} {
                    ns_log Notice "acs-mail-lite: couldn't remove message"
                }
                continue
            }

	    # Try to invoke package-specific procedure for special treatment
	    # of mail bounces
	    catch {acs_sc::invoke -contract AcsMailLite -operation MailBounce -impl [string map {- _} [apm_package_key_from_id $package_id]] -call_args [list [array get email_headers] $body]}
	    
	    # Okay, we have a bounce for a system user
	    # Check if the user has been marked as bouncing mail
	    # if the user is bouncing mail, we simply disgard the
	    # bounce since it was sent before the user's email was
	    # disabled.

	    ns_log Debug "Bounce checking: $to, $user_id"

	    if { ![bouncing_user_p -user_id $user_id] } {
                ns_log Notice "acs-mail-lite: Bouncing email from user $user_id"
		# record the bounce in the database
		db_dml record_bounce {}

		if {![db_resultrows]} {
		    db_dml insert_bounce {}
		}
	    }
            catch {ns_unlink $msg}
        }
    }
    
    #---------------------------------------
    ad_proc -public scan_replies {} {
        Scheduled procedure that will scan for bounced mails
    } {
	# Make sure that only one thread is processing the queue at a time.
	if {[nsv_incr acs_mail_lite check_bounce_p] > 1} {
	    nsv_incr acs_mail_lite check_bounce_p -1
	    return
	}

	with_finally -code {
	    ns_log Debug "acs-mail-lite: about to load qmail queue for [mail_dir]"
	    load_mails -queue_dir [mail_dir]
	} -finally {
	    nsv_incr acs_mail_lite check_bounce_p -1
	}
    }

    #---------------------------------------
    ad_proc -private check_bounces { } {
	Daily proc that sends out warning mail that emails
	are bouncing and disables emails if necessary
    } {
	set max_bounce_count [get_parameter -name MaxBounceCount -default 10]
	set max_days_to_bounce [get_parameter -name MaxDaysToBounce -default 3]
	set notification_interval [get_parameter -name NotificationInterval -default 7]
	set max_notification_count [get_parameter -name MaxNotificationCount -default 4]
	set notification_sender [get_parameter -name NotificationSender -default "reminder@[address_domain]"]

	# delete all bounce-log-entries for users who received last email
	# X days ago without any bouncing (parameter)
	db_dml delete_log_if_no_recent_bounce {}

	# disable mail sending for users with more than X recently
	# bounced mails
	db_dml disable_bouncing_email {}

	# notify users of this disabled mail sending
	db_dml send_notification_to_bouncing_email {}

	# now delete bounce log for users with disabled mail sending
	db_dml delete_bouncing_users_from_log {}

	set subject "[ad_system_name] Email Reminder"

	# now periodically send notifications to users with
	# disabled email to tell them how to reenable the email
	set notifications [db_list_of_ns_sets get_recent_bouncing_users {}]

	# send notification to users with disabled email
	foreach notification $notifications {
	    set notification_list [util_ns_set_to_list -set $notification]
	    array set user $notification_list
	    set user_id $user(user_id)

	    set body "Dear $user(name),\n\nDue to returning mails from your email account, we currently do not send you any email from our system. To reenable your email account, please visit\n[ad_url]/register/restore-bounce?[export_url_vars user_id]"

	    send -to_addr $notification_list -from_addr $notification_sender -subject $subject -body $body -valid_email
	    ns_log Notice "Bounce notification send to user $user_id"

	    # schedule next notification
	    db_dml log_notication_sending {}
	}
    }
    
    #---------------------------------------
    ad_proc -public deliver_mail {
	-to_addr:required
	-from_addr:required
	-subject:required
	-body:required
	{-extraheaders ""}
	{-bcc ""}
	{-valid_email_p 0}
	-package_id:required
    } {
	Bounce Manager send 
	@option to_addr list of mail recipients
	@option from_addr mail sender
	@option subject mail subject
	@option body mail body
	@option extraheaders extra mail header
	@option bcc list of recipients of a mail copy
	@option valid_email_p flag if email needs to be checked if it's bouncing or
	        if calling code already made sure that the receiving email addresses
	        are not bouncing (this increases performance if mails are send in a batch process)
	@option package_id package_id of the sending package
	        (needed to call package-specific code to deal with bounces)
    } {
	set msg "Subject: $subject\nDate: [ns_httptime [ns_time]]"
	
	array set headers $extraheaders
	set message_id $headers(Message-Id)

	foreach {key value} $extraheaders {
	    append msg "\n$key\: $value"
	}

	## Blank line between headers and body
	append msg "\n\n$body\n"

        # ----------------------------------------------------
        # Rollout support
        # ----------------------------------------------------
        # if set in etc/config.tcl, then
        # packages/acs-tcl/tcl/rollout-email-procs.tcl will rename a
        # proc to ns_sendmail. So we simply call ns_sendmail instead
        # of the sendmail bin if the EmailDeliveryMode parameter is
        # set to anything other than default - JFR
        #-----------------------------------------------------
        set delivery_mode [ns_config ns/server/[ns_info server]/acs/acs-rollout-support EmailDeliveryMode] 

        if {![empty_string_p $delivery_mode]
            && ![string equal $delivery_mode default]
        } {
            # The to_addr has been put in an array, and returned. Now
            # it is of the form: email email_address name namefromdb
            # user_id user_id_if_present_or_empty_string
            set to_address "[lindex $to_addr 1] ([lindex $to_addr 3])"
            set eh [util_list_to_ns_set $extraheaders]
            ns_sendmail $to_address $from_addr $subject $body $eh $bcc
        } else {

            if { [string equal [bounce_sendmail] "SMTP"] } {
                ## Terminate body with a solitary period
                foreach line [split $msg "\n"] { 
                    if {[string match . [string trim $line]]} {
                        append data .
                    }
		    #AG: ensure no \r\r\n terminations.
		    set trimmed_line [string trimright $line \r]
		    append data "$trimmed_line\r\n"
                }
                append data .
                
                smtp -from_addr $from_addr -sendlist $to_addr -msg $data -valid_email_p $valid_email_p -message_id $message_id -package_id $package_id
                if {![empty_string_p $bcc]} {
                    smtp -from_addr $from_addr -sendlist $bcc -msg $data -valid_email_p $valid_email_p -message_id $message_id -package_id $package_id
                }
                
            } else {
                sendmail -from_addr $from_addr -sendlist $to_addr -msg $msg -valid_email_p $valid_email_p -message_id $message_id -package_id $package_id
                if {![empty_string_p $bcc]} {
                    sendmail -from_addr $from_addr -sendlist $bcc -msg $msg -valid_email_p $valid_email_p -message_id $message_id -package_id $package_id
                }
            }
            
            
        }
    }
    
    #---------------------------------------
    ad_proc -private sendmail {
	-from_addr:required
        -sendlist:required
	-msg:required
	{-valid_email_p 0}
	{-cc ""}
	-message_id:required
	-package_id:required
    } {
	Sending mail through sendmail.
	@option from_addr mail sender
	@option sendlist list of mail recipients
	@option msg mail to be sent (subject, header, body)
	@option valid_email_p flag if email needs to be checked if it's bouncing or
	        if calling code already made sure that the receiving email addresses
	        are not bouncing (this increases performance if mails are send in a batch process)
	@option message_id message-id of the mail
	@option package_id package_id of the sending package
	        (needed to call package-specific code to deal with bounces)
    } {
	array set rcpts $sendlist
	if {[info exists rcpts(email)]} {
	    foreach rcpt $rcpts(email) rcpt_id $rcpts(user_id) rcpt_name $rcpts(name) {
		if { $valid_email_p || ![bouncing_email_p -email $rcpt] } {
		    with_finally -code {
			set sendmail [list [bounce_sendmail] "-f[bounce_address -user_id $rcpt_id -package_id $package_id -message_id $message_id]" "-t" "-i"]
			
			# add username if it exists
			if {![empty_string_p $rcpt_name]} {
			    set pretty_to "$rcpt_name <$rcpt>"
			} else {
			    set pretty_to $rcpt
			}
			
			# substitute all "\r\n" with "\n", because piped text should only contain "\n"
			regsub -all "\r\n" $msg "\n" msg
			
			if {[catch {
			    set err1 {}
			    set f [open "|$sendmail" "w"]
			    puts $f "From: $from_addr\nTo: $pretty_to\nCC: $cc\n$msg"
			    set err1 [close $f]
			} err2]} {
			    ns_log Error "Attempt to send From: $from_addr\nTo: $pretty_to\n$msg failed.\nError $err1 : $err2"
			}
		    } -finally {
		    }
		} else {
		    ns_log Notice "acs-mail-lite: Email bouncing from $rcpt, mail not sent and deleted from queue"
		}
		# log mail sending time
		if {![empty_string_p $rcpt_id]} { log_mail_sending -user_id $rcpt_id }
	    }
	}
    }

    #---------------------------------------
    ad_proc -private smtp {
	-from_addr:required
	-sendlist:required
	-msg:required
	{-valid_email_p 0}
	-message_id:required
	-package_id:required
    } {
	Sending mail through smtp.
	@option from_addr mail sender
	@option sendlist list of mail recipients
	@option msg mail to be sent (subject, header, body)
	@option valid_email_p flag if email needs to be checked if it's bouncing or
	        if calling code already made sure that the receiving email addresses
	        are not bouncing (this increases performance if mails are send in a batch process)
	@option message_id message-id of the mail
	@option package_id package_id of the sending package
	        (needed to call package-specific code to deal with bounces)
    } { 
	set smtp [ns_config ns/parameters smtphost]
	if {[empty_string_p $smtp]} {
	    set smtp [ns_config ns/parameters mailhost]
	}
	if {[empty_string_p $smtp]} {
	    set smtp localhost
	}
	set timeout [ns_config ns/parameters smtptimeout]
	if {[empty_string_p $timeout]} {
	    set timeout 60
	}
	set smtpport [ns_config ns/parameters smtpport]
	if {[empty_string_p $smtpport]} {
	    set smtpport 25
	}
	array set rcpts $sendlist
        foreach rcpt $rcpts(email) rcpt_id $rcpts(user_id) rcpt_name $rcpts(name) {
	    if { $valid_email_p || ![bouncing_email_p -email $rcpt] } {
		# add username if it exists
		if {![empty_string_p $rcpt_name]} {
		    set pretty_to "$rcpt_name <$rcpt>"
		} else {
		    set pretty_to $rcpt
		}

		set msg "From: $from_addr\r\nTo: $pretty_to\r\n$msg"
		set mail_from [bounce_address -user_id $rcpt_id -package_id $package_id -message_id $message_id]

		## Open the connection
		set sock [ns_sockopen $smtp $smtpport]
		set rfp [lindex $sock 0]
		set wfp [lindex $sock 1]
		
		## Perform the SMTP conversation
		with_finally -code {
		    _ns_smtp_recv $rfp 220 $timeout
		    _ns_smtp_send $wfp "HELO [ns_info hostname]" $timeout
		    _ns_smtp_recv $rfp 250 $timeout
		    _ns_smtp_send $wfp "MAIL FROM:<$mail_from>" $timeout
		    _ns_smtp_recv $rfp 250 $timeout
		    _ns_smtp_send $wfp "RCPT TO:<$rcpt>" $timeout
		    _ns_smtp_recv $rfp 250 $timeout
		    _ns_smtp_send $wfp DATA $timeout
		    _ns_smtp_recv $rfp 354 $timeout
		    _ns_smtp_send $wfp $msg $timeout
		    _ns_smtp_recv $rfp 250 $timeout
		    _ns_smtp_send $wfp QUIT $timeout
		    _ns_smtp_recv $rfp 221 $timeout
		} -finally {
		    ## Close the connection
		    close $rfp
		    close $wfp
		}
	    } else {
		ns_log Notice "acs-mail-lite: Email bouncing from $rcpt, mail not sent and deleted from queue"
	    }
	    # log mail sending time
	    if {![empty_string_p $rcpt_id]} { log_mail_sending -user_id $rcpt_id }
	}
    }

    #---------------------------------------
    ad_proc -private get_address_array {
	-addresses:required
    } {	Checks if passed variable is already an array of emails,
	user_names and user_ids. If not, get the additional data
	from the db and return the full array.
	@option addresses variable to checked for array
	@returns array of emails, user_names and user_ids to be used
	         for the mail procedures
    } {
	if {[catch {array set address_array $addresses}]
	    || ![string equal [lsort [array names address_array]] [list email name user_id]]} {

	    # either user just passed a normal address-list or
	    # user passed an array, but forgot to provide user_ids
	    # or user_names, so we have to get this data from the db

	    if {![info exists address_array(email)]} {
		# so user passed on a normal address-list
		set address_array(email) $addresses
	    }

	    set address_list [list]
	    foreach email $address_array(email) {
		# strip out only the emails from address-list
		lappend address_list [string tolower [parse_email_address -email $email]]
	    }

	    array unset address_array
	    # now get the user_names and user_ids
	    foreach email $address_list {
		set email [string tolower $email]
		if {[db_0or1row get_user_name_and_id ""]} {
		    lappend address_array(email) $email
		    lappend address_array(name) $user_name
		    lappend address_array(user_id) $user_id
		} else {
		    lappend address_array(email) $email
		    lappend address_array(name) ""
		    lappend address_array(user_id) ""
		}
	    }
	}
	return [array get address_array]
    }
    
    #---------------------------------------
    ad_proc -public send {
	-send_immediately:boolean
	-valid_email:boolean
        -to_addr:required
        -from_addr:required
        {-subject ""}
        -body:required
        {-extraheaders ""}
        {-bcc ""}
	{-package_id ""}
	-no_callback:boolean
    } {
        Reliably send an email message.

	@option send_immediately Switch that lets the mail send directly without adding it to the mail queue first.
	@option valid_email Switch that avoids checking if the email to be mailed is not bouncing
	@option to_addr List of mail-addresses or array of email,name,user_id containing lists of users to be mailed
	@option from_addr mail sender
	@option subject mail subject
	@option body mail body
	@option extraheaders extra mail headers in an ns_set
	@option bcc see to_addr
	@option package_id To be used for calling a package-specific proc when mail has bounced
	@option no_callback_p Boolean that indicates if callback should be executed or not. If you don't provide it it will execute callbacks
        @returns the Message-Id of the mail
    } {

	## Extract "from" email address
	set from_addr [parse_email_address -email $from_addr]

	set from_party_id [party::get_by_email -email $from_addr] 
	set to_party_id [party::get_by_email -email $to_addr] 
	
	## Get address-array with email, name and user_id
	set to_addr [get_address_array -addresses [string map {\n "" \r ""} $to_addr]]
	if {![empty_string_p $bcc]} {
	    set bcc [get_address_array -addresses [string map {\n "" \r ""} $bcc]]
	}

        if {![empty_string_p $extraheaders]} {
            set eh_list [util_ns_set_to_list -set $extraheaders]
        } else {
            set eh_list ""
        }

        # Subject cannot contain newlines -- replace with spaces
        regsub -all {\n} $subject { } subject

	set message_id [generate_message_id]
        lappend eh_list "Message-Id" $message_id

	if {[empty_string_p $package_id]} {
	    if [ad_conn -connected_p] {
		set package_id [ad_conn package_id]
	    } else {
		set package_id ""
	    }
	}

        # Subject can not be longer than 200 characters
        if { [string length $subject] > 200 } {
            set subject "[string range $subject 0 196]..."
        }

	# check, if send_immediately is set
	# if not, take global parameter
	if {$send_immediately_p} {
	    set send_p $send_immediately_p
	} else {
	    # if parameter is not set, get the global setting
	    set send_p [parameter::get -package_id [get_package_id] -parameter "send_immediately" -default 0]
	}


	# if send_p true, then start acs_mail_lite::send_immediately, so mail is not stored in the db before delivery
	if { $send_p } {
	    acs_mail_lite::send_immediately -to_addr $to_addr -from_addr $from_addr -subject $subject -body $body -extraheaders $eh_list -bcc $bcc -valid_email_p $valid_email_p -package_id $package_id
	} else {
	    # else, store it in the db and let the sweeper deliver the mail
	    db_dml create_queue_entry {}
	}

	if { !$no_callback_p } {
	    callback acs_mail_lite::send \
		-package_id $package_id \
		-from_party_id $from_party_id \
		-to_party_id $to_party_id \
		-body $body \
		-message_id $message_id \
		-subject $subject
	}

        return $message_id
    }


    #---------------------------------------
    # complex_send
    # created ... by ...
    # modified 2006/07/25 by nfl: new param. alternative_part_p
    #                             and creation of multipart/alternative
    # 2006/../.. new created as an frontend to the old complex_send that now is called complex_send_immediatly
    # 2006/11/17 modified (nfl)
    #---------------------------------------
    ad_proc -public complex_send {
	-send_immediately:boolean
	-valid_email:boolean
	{-to_party_ids ""}
	{-cc_party_ids ""}
	{-bcc_party_ids ""}
	{-to_group_ids ""}
	{-cc_group_ids ""}
	{-bcc_group_ids ""}
        {-to_addr ""}
	{-cc_addr ""}
	{-bcc_addr ""}
        -from_addr:required
        {-subject ""}
        -body:required
	{-package_id ""}
	{-files ""}
	{-file_ids ""}
	{-folder_ids ""}
	{-mime_type "text/plain"}
	{-object_id ""}
	{-single_email_p ""}
	{-no_callback_p ""}
	{-extraheaders ""}
        {-alternative_part_p ""}
	-single_email:boolean
	-no_callback:boolean 
	-use_sender:boolean
    } {

	Prepare an email to be send with the option to pass in a list
	of file_ids as well as specify an html_body and a mime_type. It also supports multiple "TO" recipients as well as CC
	and BCC recipients. Runs entirely off MIME and SMTP to achieve this. 
	For backward compatibility a switch "single_email_p" is added.

	@param send_immediately The email is send immediately and not stored in the acs_mail_lite_queue
	
	@param to_party_ids list of party ids to whom we send this email

	@param cc_party_ids list of party ids to whom we send this email in "CC"

	@param bcc_party_ids list of party ids to whom we send this email in "BCC"

	@param to_party_ids list of group_ids to whom we send this email

	@param cc_party_ids list of group_ids to whom we send this email in "CC"

	@param bcc_party_ids list of group_ids to whom we send this email in "BCC"

	@param to_addr List of e-mail addresses to send this mail to. We will figure out the name if possible.

	@param from_addr E-Mail address of the sender. We will try to figure out the name if possible.
	
	@param subject of the email
	
	@param body Text body of the email
	
	@param cc_addr List of CC Users e-mail addresses to send this mail to. We will figure out the name if possible. Only useful if single_email is provided. Otherwise the CC users will be send individual emails.

	@param bcc_addr List of CC Users e-mail addresses to send this mail to. We will figure out the name if possible. Only useful if single_email is provided. Otherwise the CC users will be send individual emails.

	@param package_id Package ID of the sending package
	
	@param files List of file_title, mime_type, file_path (as in full path to the file) combination of files to be attached

	@param folder_ids ID of the folder who's content will be send along with the e-mail.

	@param file_ids List of file ids (items or revisions) to be send as attachments. This will only work with files stored in the file system.

	@param mime_type MIME Type of the mail to send out. Can be "text/plain", "text/html".

	@param object_id The ID of the object that is responsible for sending the mail in the first place

	@param extraheaders List of keywords and their values passed in for headers. Interesting ones are: "Precedence: list" to disable autoreplies and mark this as a list message. This is as list of lists !!

	@param single_email Boolean that indicates that only one mail will be send (in contrast to one e-mail per recipient). 

	@param no_callback Boolean that indicates if callback should be executed or not. If you don't provide it it will execute callbacks	
	@param single_email_p Boolean that indicates that only one mail will be send (in contrast to one e-mail per recipient). Used so we can set a variable in the callers environment to call complex_send.

	@param no_callback_p Boolean that indicates if callback should be executed or not. If you don't provide it it will execute callbacks. Used so we can set a variable in the callers environment to call complex_send.

	@param use_sender Boolean indicating that from_addr should be used regardless of fixed-sender parameter

        @param alternative_part_p Boolean whether or not the code generates a multipart/alternative mail (text/html)
    } {

	# check, if send_immediately is set
	# if not, take global parameter
	if {$send_immediately_p} {
	    set send_p $send_immediately_p
	} else {
	    # if parameter is not set, get the global setting
	    set send_p [parameter::get -package_id [get_package_id] -parameter "send_immediately" -default 0]
	}

	# if send_p true, then start acs_mail_lite::send_immediately, so mail is not stored in the db before delivery
	if { $send_p } {
	    acs_mail_lite::complex_send_immediately \
		-to_party_ids $to_party_ids \
		-cc_party_ids $cc_party_ids \
		-bcc_party_ids $bcc_party_ids \
		-to_group_ids $to_group_ids \
		-cc_group_ids $cc_group_ids \
		-bcc_group_ids $bcc_group_ids \
		-to_addr $to_addr \
		-cc_addr $cc_addr \
		-bcc_addr $bcc_addr \
		-from_addr $from_addr \
		-subject $subject \
		-body $body \
		-package_id $package_id \
		-files $files \
		-file_ids $file_ids \
		-folder_ids $folder_ids \
		-mime_type $mime_type \
		-object_id $object_id \
		-single_email_p $single_email_p \
		-no_callback_p $no_callback_p \
		-extraheaders $extraheaders \
		-alternative_part_p $alternative_part_p \
		-use_sender_p $use_sender_p
	} else {
	    # else, store it in the db and let the sweeper deliver the mail
	    set creation_date [clock format [clock seconds] -format "%Y.%m.%d %H:%M:%S"]
	    set locking_server ""
	    db_dml create_complex_queue_entry {}
	}
    }

    #---------------------------------------
    # complex_send
    # created ... by ...
    # modified 2006/07/25 by nfl: new param. alternative_part_p
    #                             and creation of multipart/alternative    
    # 2006/../.. Renamed to complex_send_immediately
    #---------------------------------------
    ad_proc -public complex_send_immediately {
	-valid_email:boolean
	{-to_party_ids ""}
	{-cc_party_ids ""}
	{-bcc_party_ids ""}
	{-to_group_ids ""}
	{-cc_group_ids ""}
	{-bcc_group_ids ""}
        {-to_addr ""}
	{-cc_addr ""}
	{-bcc_addr ""}
        -from_addr:required
        {-subject ""}
        -body:required
	{-package_id ""}
	{-files ""}
	{-file_ids ""}
	{-folder_ids ""}
	{-mime_type "text/plain"}
	{-object_id ""}
	{-single_email_p ""}
	{-no_callback_p ""}
	{-extraheaders ""}
        {-alternative_part_p ""}
	{-use_sender_p ""}
    } {

	Prepare an email to be send immediately with the option to pass in a list
	of file_ids as well as specify an html_body and a mime_type. It also supports multiple "TO" recipients as well as CC
	and BCC recipients. Runs entirely off MIME and SMTP to achieve this. 
	For backward compatibility a switch "single_email_p" is added.

	
	@param to_party_ids list of party ids to whom we send this email

	@param cc_party_ids list of party ids to whom we send this email in "CC"

	@param bcc_party_ids list of party ids to whom we send this email in "BCC"

	@param to_party_ids list of group_ids to whom we send this email

	@param cc_party_ids list of group_ids to whom we send this email in "CC"

	@param bcc_party_ids list of group_ids to whom we send this email in "BCC"

	@param to_addr List of e-mail addresses to send this mail to. We will figure out the name if possible.

	@param from_addr E-Mail address of the sender. We will try to figure out the name if possible.
	
	@param subject of the email
	
	@param body Text body of the email
	
	@param cc_addr List of CC Users e-mail addresses to send this mail to. We will figure out the name if possible. Only useful if single_email is provided. Otherwise the CC users will be send individual emails.

	@param bcc_addr List of CC Users e-mail addresses to send this mail to. We will figure out the name if possible. Only useful if single_email is provided. Otherwise the CC users will be send individual emails.

	@param package_id Package ID of the sending package
	
	@param files List of file_title, mime_type, file_path (as in full path to the file) combination of files to be attached

	@param folder_ids ID of the folder who's content will be send along with the e-mail.

	@param file_ids List of file ids (items or revisions) to be send as attachments. This will only work with files stored in the file system.

	@param mime_type MIME Type of the mail to send out. Can be "text/plain", "text/html".

	@param object_id The ID of the object that is responsible for sending the mail in the first place

	@param extraheaders List of keywords and their values passed in for headers. Interesting ones are: "Precedence: list" to disable autoreplies and mark this as a list message. This is as list of lists !!

	@param single_email Boolean that indicates that only one mail will be send (in contrast to one e-mail per recipient). 

	@param no_callback Boolean that indicates if callback should be executed or not. If you don't provide it it will execute callbacks	
	@param single_email_p Boolean that indicates that only one mail will be send (in contrast to one e-mail per recipient). Used so we can set a variable in the callers environment to call complex_send.

	@param no_callback_p Boolean that indicates if callback should be executed or not. If you don't provide it it will execute callbacks. Used so we can set a variable in the callers environment to call complex_send.

	@param use_sender Boolean indicating that from_addr should be used regardless of fixed-sender parameter

        @param alternative_part_p Boolean whether or not the code generates a multipart/alternative mail (text/html)
    } {

	set mail_package_id [apm_package_id_from_key "acs-mail-lite"]
	if {[empty_string_p $package_id]} {
	    set package_id $mail_package_id
	}

	# We check if the parameter 
	set fixed_sender [parameter::get -parameter "FixedSenderEmail" \
			      -package_id $mail_package_id]

	if { ![empty_string_p $fixed_sender] && !$use_sender_p} {
	    set sender_addr $fixed_sender
	} else {
	    set sender_addr $from_addr
	}

	# Get the SMTP Parameters
	set smtp [parameter::get -parameter "SMTPHost" \
	     -package_id $mail_package_id -default [ns_config ns/parameters mailhost]]
	if {[empty_string_p $smtp]} {
	    set smtp localhost
	}

	set timeout [parameter::get -parameter "SMTPTimeout" \
	     -package_id $mail_package_id -default  [ns_config ns/parameters smtptimeout]]
	if {[empty_string_p $timeout]} {
	    set timeout 60
	}

	set smtpport [parameter::get -parameter "SMTPPort" \
	     -package_id [apm_package_id_from_key "acs-mail-lite"] -default 25]

	set smtpuser [parameter::get -parameter "SMTPUser" \
	     -package_id [apm_package_id_from_key "acs-mail-lite"]]

	set smtppassword [parameter::get -parameter "SMTPPassword" \
	     -package_id [apm_package_id_from_key "acs-mail-lite"]]

        # default values for alternative_part_p
        # TRUE on mime_type text/html
        # FALSE on mime_type text/plain
        # if { [empty_string_p $alternative_part_p] } {    ...} 
        if { $alternative_part_p eq "" } {
	    if { $mime_type eq "text/plain" } {
		#set alternative_part_p FALSE
                set alternative_part_p "0"
            } else {
                #set alternative_part_p TRUE
                set alternative_part_p "1"
            }
        }

	set party_id($from_addr) [party::get_by_email -email $from_addr]
	
	# Deal with the sender address. Only change the from string if we find a party_id
	# This should take care of anyone parsing in an email which is already formated with <>.
	set party_id($sender_addr) [party::get_by_email -email $sender_addr]
	if {[exists_and_not_null party_id($sender_addr)]} {
	    set from_string "\"[party::name -email $sender_addr]\" <${sender_addr}>"
	} else {
	    set from_string $sender_addr
	}

        # decision between normal or multipart/alternative body
        if { $alternative_part_p eq "0"} {
  	    # Set the message token
	    set message_token [mime::initialize -canonical "$mime_type" -string "$body"]
        } else {
            # build multipart/alternative
	    if { $mime_type eq "text/plain" } {
		set message_text_part [mime::initialize -canonical "text/plain" -string "$body"]
                set converted [ad_text_to_html "$body"]
                set message_html_part [mime::initialize -canonical "text/html" -string "$converted"]
            } else {
		set message_html_part [mime::initialize -canonical "text/html" -string "$body"]
                set converted [ad_html_to_text "$body"]
                set message_text_part [mime::initialize -canonical "text/plain" -string "$converted"]
            }   
            set message_token [mime::initialize -canonical multipart/alternative -parts [list $message_text_part $message_html_part]]
            # see RFC 2046, 5.1.4.  Alternative Subtype, for further information/reference (especially order of parts)  
        }


	# encode all attachments in base64
    
	set tokens [list $message_token]
	set item_ids [list]

	if {[exists_and_not_null file_ids]} {

	    # Check if we are dealing with revisions or items.
	    foreach file_id $file_ids {
		set item_id [content::revision::item_id -revision_id $file_id]
		if {[string eq "" $item_id]} {
		    lappend item_ids $file_id
		} else {
		    lappend item_ids $item_id
		}
	    }

	    db_foreach get_file_info "select r.mime_type,r.title, r.content as filename
	           from cr_revisions r, cr_items i
	           where r.revision_id = i.latest_revision
                   and i.item_id in ([join $item_ids ","])" {
		       lappend tokens [mime::initialize -param [list name "[ad_quotehtml $title]"] -header [list "Content-Disposition" "attachment; filename=$title"] -header [list Content-Description $title] -canonical $mime_type -file "[cr_fs_path]$filename"]
		   }
	}
	
	if {![string eq "" $files]} {
	    foreach file $files {
		lappend tokens [mime::initialize -param [list name "[ad_quotehtml [lindex $file 0]]"] -canonical [lindex $file 1] -file "[lindex $file 2]"]
	    }
	}

	if {[exists_and_not_null folder_ids]} {
	    
	    foreach folder_id $folder_ids {
		db_foreach get_file_info {select r.revision_id,r.mime_type,r.title, i.item_id, r.content as filename
		    from cr_revisions r, cr_items i
		    where r.revision_id = i.latest_revision and i.parent_id = :folder_id} {
			lappend tokens [mime::initialize -param [list name "[ad_quotehtml $title]"] -canonical $mime_type -file "[cr_fs_path]$filename"]
			lappend item_ids $item_id
		    }
	    } 
	}


	#### Now we start with composing the mail message ####

	set multi_token [mime::initialize -canonical multipart/mixed -parts "$tokens"]

	# Set the message_id
	set message_id "[mime::uniqueID]"
	mime::setheader $multi_token "message-id" "[mime::uniqueID]"
	
	# Set the date
	mime::setheader $multi_token date "[mime::parsedatetime -now proper]"

	# 2006/09/25 nfl/cognovis
	# subject: convert 8-bit characters into MIME encoded words
	# see http://tools.ietf.org/html/rfc2047
	# note: we always assume ISO-8859-15 !!!
	set subject_encoded $subject
	for {set i 128} {$i<256} {incr i} {
	    set eight_bit_char [format %c $i]
	    set mime_encoded_word "=?"
	    append mime_encoded_word "ISO-8859-15"
	    append mime_encoded_word "?"
	    append mime_encoded_word "B"
	    append mime_encoded_word "?"
	    append mime_encoded_word [base64::encode $eight_bit_char]
	    append mime_encoded_word "?="
	    set subject_encoded [regsub -all $eight_bit_char $subject_encoded $mime_encoded_word]
	}
	
	# 2006/09/25 nfl/cognovis
	# subject: convert 8-bit characters into MIME encoded words
	# see http://tools.ietf.org/html/rfc2047
	# note: we always assume ISO-8859-1 !!!
	for {set i 128} {$i<256} {incr i} {
	    set eight_bit_char [format %c $i]
	    set mime_encoded_word "=?"
	    append mime_encoded_word "ISO-8859-1"
	    append mime_encoded_word "?"
	    append mime_encoded_word "B"
	    append mime_encoded_word "?"
	    append mime_encoded_word [base64::encode $eight_bit_char]
	    append mime_encoded_word "?="
	    set subject [regsub -all $eight_bit_char $subject $mime_encoded_word]
	}
	
	# Set the subject
	#2006/09/25 mime::setheader $multi_token Subject "$subject"
	mime::setheader $multi_token Subject "$subject_encoded"

	foreach header $extraheaders {
	    mime::setheader $multi_token "[lindex $header 0]" "[lindex $header 1]"
	}

 	set packaged [mime::buildmessage $multi_token]

       	# Now the To recipients
	set to_list [list]

	foreach email $to_addr {
	    set party_id($email) [party::get_by_email -email $email]
	    if {$party_id($email) eq ""} {
		# We could not find a party_id, write the email alone
		lappend to_list $email
	    } else {	    
		# Make sure we are not sending the same e-mail twice to the same person
		if {[lsearch $to_party_ids $party_id($email)] < 0} {
		    lappend to_party_ids $party_id($email)
		}
	    }
	}

	# Run through the party_ids and check if a group is in there.
	set new_to_party_ids [list]
	foreach to_id $to_party_ids {
	    if {[group::group_p -group_id $to_id]} {
		lappend to_group_ids $to_id
	    } else {
		if {[lsearch $new_to_party_ids $to_id] < 0} {
		    lappend new_to_party_ids $to_id
		}
	    }
	}

	foreach group_id $to_group_ids {
	    foreach to_id [group::get_members -group_id $group_id] {
		if {[lsearch $new_to_party_ids $to_id] < 0} {
		    lappend new_to_party_ids $to_id
		}
	    } 
	}

	# New to party ids contains now the unique party_ids of members of the groups along with the parties
	set to_party_ids $new_to_party_ids

	# Now the Cc recipients
	set cc_list [list]

	foreach email $cc_addr {
	    set party_id($email) [party::get_by_email -email $email]
	    if {$party_id($email) eq ""} {
		# We could not find a party_id, write the email alone
		lappend cc_list $email
	    } else {	    
		# Make sure we are not sending the same e-mail twice to the same person
		if {[lsearch $cc_party_ids $party_id($email)] < 0} {
		    lappend cc_party_ids $party_id($email)
		}
	    }
	}

	# Run through the party_ids and check if a group is in there.
	set new_cc_party_ids [list]
	foreach cc_id $cc_party_ids {
	    if {[group::group_p -group_id $cc_id]} {
		lappend cc_group_ids $cc_id
	    } else {
		if {[lsearch $new_cc_party_ids $cc_id] < 0} {
		    lappend new_cc_party_ids $cc_id
		}
	    }
	}
	    
	foreach group_id $cc_group_ids {
	    foreach cc_id [group::get_members -group_id $group_id] {
		if {[lsearch $new_cc_party_ids $cc_id] < 0} {
		    lappend new_cc_party_ids $cc_id
		}
	    } 
	}

	# New to party ids contains now the unique party_ids of members of the groups along with the parties
	set cc_party_ids $new_cc_party_ids

	# Now the Bcc recipients
	set bcc_list [list]

	foreach email $bcc_addr {
	    set party_id($email) [party::get_by_email -email $email]
	    if {$party_id($email) eq ""} {
		# We could not find a party_id, write the email alone
		lappend bcc_list $email
	    } else {	    
		# Make sure we are not sending the same e-mail twice to the same person
		if {[lsearch $bcc_party_ids $party_id($email)] < 0} {
		    lappend bcc_party_ids $party_id($email)
		}
	    }
	}

	# Run through the party_ids and check if a group is in there.
	set new_bcc_party_ids [list]
	foreach bcc_id $bcc_party_ids {
	    if {[group::group_p -group_id $bcc_id]} {
		lappend bcc_group_ids $bcc_id
	    } else {
		if {[lsearch $new_bcc_party_ids $bcc_id] < 0} {
		    lappend new_bcc_party_ids $bcc_id
		}
	    }
	}
	    
	foreach group_id $bcc_group_ids {
	    foreach bcc_id [group::get_members -group_id $group_id] {
		if {[lsearch $new_bcc_party_ids $bcc_id] < 0} {
		    lappend new_bcc_party_ids $bcc_id
		}
	    } 
	}

	# New to party ids contains now the unique party_ids of members of the groups along with the parties
	set bcc_party_ids $new_bcc_party_ids

	# Rollout support (see above for details)

	ns_log Notice "acs-mail-lite:complex_send:: From String: $from_string"
	set delivery_mode [ns_config ns/server/[ns_info server]/acs/acs-rollout-support EmailDeliveryMode] 
	if {![empty_string_p $delivery_mode]
	    && ![string equal $delivery_mode default]
	} {
	    set eh [util_list_to_ns_set $extraheaders]
	    ns_sendmail $to_addr $sender_addr $subject $packaged $eh $bcc_addr
	    #Close all mime tokens
	    mime::finalize $multi_token -subordinates all
	} else {

	    if {$single_email_p} {
		
		#############################
		# 
		# One mail to all
		# 
		#############################

		# First join the emails without parties for the callback.
		set to_addr_string [join $to_list ","]
		set cc_addr_string [join $cc_list ","]
		set bcc_addr_string [join $bcc_list ","]

		# Append the entries from the system users to the e-mail
		foreach party $to_party_ids {
		    lappend to_list "\"[party::name -party_id $party]\" <[party::email_not_cached -party_id $party]>"
		}
		
		foreach party $cc_party_ids {
		    lappend cc_list "\"[party::name -party_id $party]\" <[party::email_not_cached -party_id $party]>"
		}
		
		foreach party $bcc_party_ids {
		    lappend bcc_list "\"[party::name -party_id $party]\" <[party::email_not_cached -party_id $party]>"
		}

		smtp::sendmessage $multi_token \
		    -header [list From "$from_string"] \
		    -header [list To "[join $to_list ","]"] \
		    -header [list CC "[join $cc_list ","]"] \
		    -header [list BCC "[join $bcc_list ","]"] \
		    -servers $smtp \
		    -ports $smtpport \
		    -username $smtpuser \
		    -password $smtppassword
		
		#Close all mime tokens
		mime::finalize $multi_token -subordinates all
		
		if { !$no_callback_p } {
		    callback acs_mail_lite::complex_send \
			-package_id $package_id \
			-from_party_id [party::get_by_email -email $sender_addr] \
			-to_party_ids $to_party_ids \
			-cc_party_ids $cc_party_ids \
			-bcc_party_ids $bcc_party_ids \
			-to_addr $to_addr_string \
			-cc_addr $cc_addr_string \
			-bcc_addr $bcc_addr_string \
			-body $body \
			-message_id $message_id \
			-subject $subject \
			-object_id $object_id \
			-file_ids $item_ids
		}

	    
	    } else {
		
		####################################################################
		# 
		# Individual E-Mails. 
		# All recipients, (regardless who they are) get a separate E-Mail
		#
		####################################################################

		# We send individual e-mails. First the ones that do not have a party_id
		set recipient_list [concat $to_list $cc_list $bcc_list]
		foreach email $recipient_list {
		    set message_id [mime::uniqueID]

		    smtp::sendmessage $multi_token \
			-header [list From "$from_string"] \
			-header [list To "$email"] \
			-servers $smtp \
			-ports $smtpport \
			-username $smtpuser \
			-password $smtppassword

		    if { !$no_callback_p } {
			callback acs_mail_lite::complex_send \
			    -package_id $package_id \
			    -from_party_id $party_id($from_addr) \
			    -to_addr $email \
			    -body $body \
			    -message_id $message_id \
			    -subject $subject \
			    -object_id $object_id \
			    -file_ids $item_ids
		    }
		}

		# And now we send it to all the other users who actually do have a party_id
		set recipient_list [concat $to_party_ids $cc_party_ids $bcc_party_ids]
		foreach party $recipient_list {
		    set message_id [mime::uniqueID]
		    set email "\"[party::name -party_id $party]\" <[party::email_not_cached -party_id $party]>"

		    smtp::sendmessage $multi_token \
			-header [list From "$from_string"] \
			-header [list To "$email"] \
			-servers $smtp \
			-ports $smtpport \
			-username $smtpuser \
			-password $smtppassword
		    
		    if { !$no_callback_p } {
			callback acs_mail_lite::complex_send \
			    -package_id $package_id \
			    -from_party_id $party_id($from_addr) \
			    -to_party_ids $party \
			    -body $body \
			    -message_id $message_id \
			    -subject $subject \
			    -object_id $object_id \
			    -file_ids $item_ids
		    }
		}

		#Close all mime tokens
		mime::finalize $multi_token -subordinates all
	    }
	}	    
    }

    #---------------------------------------
    # 2006/11/17 Created by cognovis/nfl
    #            nsv_incr description: http://www.panoptic.com/wiki/aolserver/Nsv_incr
    #---------------------------------------    
    ad_proc -private complex_sweeper {} {
        Send messages in the acs_mail_lite_complex_queue table.
    } {
        # Make sure that only one thread is processing the queue at a time.
        if {[nsv_incr acs_mail_lite complex_send_mails_p] > 1} {
            nsv_incr acs_mail_lite complex_send_mails_p -1
            return
        }

        with_finally -code {
            db_foreach get_complex_queued_messages {} {
		# check if record is already there and free to use
		set return_id [db_string get_complex_queued_message {} -default -1]
		if {$return_id == $id} {
		    # lock this record for exclusive use
		    set locking_server [ad_conn user_id]
		    append locking_server ":"
		    append locking_server [ad_conn session_id]
		    append locking_server ":"   
		    append locking_server [ad_conn url]
		    db_dml lock_queued_message {}
		    # send the mail
		    set err [catch {
			acs_mail_lite::complex_send_immediately \
			    -to_party_ids $to_party_ids \
			    -cc_party_ids $cc_party_ids \
			    -bcc_party_ids $bcc_party_ids \
			    -to_group_ids $to_group_ids \
			    -cc_group_ids $cc_group_ids \
			    -bcc_group_ids $bcc_group_ids \
			    -to_addr $to_addr \
			    -cc_addr $cc_addr \
			    -bcc_addr $bcc_addr \
			    -from_addr $from_addr \
			    -subject $subject \
			    -body $body \
			    -package_id $package_id \
			    -files $files \
			    -file_ids $file_ids \
			    -folder_ids $folder_ids \
			    -mime_type $mime_type \
			    -object_id $object_id \
			    -single_email_p $single_email_p \
			    -no_callback_p $no_callback_p \
			    -extraheaders $extraheaders \
			    -alternative_part_p $alternative_part_p \
			    -use_sender_p $use_sender_p        
		    } errMsg]
		    if $err {
			# release the lock
			set locking_server ""
			db_dml lock_queued_message {}    
		    } else {
			# mail was sent, delete the queue entry
			db_dml delete_complex_queue_entry {}
		    }
		}
            }
        } -finally {
            nsv_incr acs_mail_lite complex_send_mails_p -1
        }
    }                 


    #---------------------------------------
    ad_proc -private sweeper {} {
        Send messages in the acs_mail_lite_queue table.
    } {
	# Make sure that only one thread is processing the queue at a time.
	if {[nsv_incr acs_mail_lite send_mails_p] > 1} {
	    nsv_incr acs_mail_lite send_mails_p -1
	    return
	}

	with_finally -code {
	    db_foreach get_queued_messages {} {
		with_finally -code {
		    deliver_mail -to_addr $to_addr -from_addr $from_addr \
			-subject $subject -body $body -extraheaders $extra_headers \
			-bcc $bcc -valid_email_p $valid_email_p \
			-package_id $package_id

		    db_dml delete_queue_entry {}
		} -finally {
		}
	    }
	} -finally {
	    nsv_incr acs_mail_lite send_mails_p -1
	}
    }

    #---------------------------------------
    ad_proc -private send_immediately {
        -to_addr:required
        -from_addr:required
        {-subject ""}
        -body:required
        {-extraheaders ""}
        {-bcc ""}
	{-valid_email_p 0}
	-package_id:required
    } {
	Procedure to send mails immediately without queuing the mail in the database for performance reasons.
	If ns_sendmail fails, the mail will be written in the db so the sweeper can send them out later.
	@option to_addr List of mail-addresses or array of email,name,user_id containing lists of users to be mailed
	@option from_addr mail sender
	@option subject mail subject
	@option body mail body
	@option extraheaders extra mail headers
	@option bcc see to_addr
	@option valid_email_p Switch that avoids checking if the email to be mailed is not bouncing
	@option package_id To be used for calling a package-specific proc when mail has bounced
    } {
	if {[catch {
	    deliver_mail -to_addr $to_addr -from_addr $from_addr -subject $subject -body $body -extraheaders $extraheaders -bcc $bcc -valid_email_p $valid_email_p -package_id $package_id
	} errmsg]} {
	    ns_log Error "acs_mail_lite::deliver_mail failed: $errmsg"
	    ns_log "Notice" "Mail info will be written in the db"
	    db_dml create_queue_entry {}
	} else {
	    ns_log "Debug" "acs_mail_lite::deliver_mail successful"
	}
    }

    #---------------------------------------
    ad_proc -private after_install {} {
	Callback to be called after package installation.
	Adds the service contract package-specific bounce management.

	@author Timo Hentschel (thentschel@sussdorff-roy.com)
    } {
	acs_sc::contract::new -name AcsMailLite -description "Callbacks for Bounce Management"
	acs_sc::contract::operation::new -contract_name AcsMailLite -operation MailBounce -input "header:string body:string" -output "" -description "Callback to handle bouncing mails"
    }

    #---------------------------------------
    ad_proc -private before_uninstall {} {
	Callback to be called before package uninstallation.
	Removes the service contract for package-specific bounce management.

	@author Timo Hentschel (thentschel@sussdorff-roy.com)
    } {
	# shouldn't we first delete the bindings?
	acs_sc::contract::delete -name AcsMailLite
    }

    #---------------------------------------
    ad_proc -private message_interpolate {
	{-values:required}
	{-text:required}
    } {
	Interpolates a set of values into a string. This is directly copied from the bulk mail package
	
	@param values a list of key, value pairs, each one consisting of a
	target string and the value it is to be replaced with.
	@param text the string that is to be interpolated
	
	@return the interpolated string
    } {
	foreach pair $values {
	    regsub -all [lindex $pair 0] $text [lindex $pair 1] text
	}
	return $text
    }

    #---------------------------------------

}
