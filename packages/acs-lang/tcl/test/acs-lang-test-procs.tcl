ad_library {
    Helper test Tcl procedures.

    @author Peter Marklund (peter@collaboraid.biz)
    @creation-date 18 October 2002
}

namespace eval lang::test {}

ad_proc lang::test::get_dir {} {
    The test directory of the acs-lang package (where this file resides).

    @author Peter Marklund (peter@collaboraid.biz)
    @creation-date 28 October 2002
} {
    return "[acs_package_root_dir acs-lang]/tcl/test"
}

ad_proc lang::test::assert_browser_locale {accept_language expect_locale} {
    Assert that with given accept language header lang::conn::browser_locale returns
    the expected locale.

    @author Peter Marklund
} {
    ns_set update [ns_conn headers] "Accept-Language" $accept_language
    set browser_locale [lang::conn::browser_locale]
    aa_equals "accept-language header \"$accept_language\"" $browser_locale $expect_locale
}





aa_register_case util__replace_temporary_tags_with_lookups {
    Primarily tests lang::util::replace_temporary_tags_with_lookups,
    Also tests the procs lang::catalog::export_messages_to_file, lang::catalog::parse,
    lang::catalog::read_file, and lang::util::get_temporary_tags_indices.

    A test tcl file and catalog file are created. The temporary tags in the
    tcl file are replaced with message lookups and keys and messages are appended
    to the catalog file.

    @author Peter Marklund (peter@collaboraid.biz)
    @creation-date 18 October 2002
} {
    # Peter NOTE: cannot get this test case to work with the rollback code in automated testing
    # and couldn't track down why. I'm threrefor resorting to manual teardown which is fragile and hairy
    
    # The files involved in the test
    set package_key acs-lang
    set test_dir [lang::test::get_dir]
    set catalog_dir [lang::catalog::package_catalog_dir $package_key]
    set catalog_file "${catalog_dir}/acs-lang.xxx_xx.ISO-8859-1.xml"
    set backup_file_suffix ".orig"
    set catalog_backup_file "${catalog_file}${backup_file_suffix}"
    regexp {^.*(packages/.*)$} $test_dir match test_dir_rel
    set tcl_file "${test_dir_rel}/test-message-tags.tcl"
    set tcl_backup_file "${tcl_file}${backup_file_suffix}"

    # The test messages to use for the catalog file
    array set messages_array [list key_1 text_1 key_2 text_2 key_3 text_3]
    # NOTE: must be kept up-to-date for teardown to work
    set expected_new_keys [list Auto_Key key_1_1] 

    # Write the test tcl file
    set tcl_file_id [open "[acs_root_dir]/$tcl_file" w]    
    set new_key_1 "_"
    set new_text_1 "Auto Key"
    set new_key_2 "key_1"
    set new_text_2 "text_1_different"
    set new_key_3 "key_1"
    set new_text_3 "$messages_array(key_1)"
    puts $tcl_file_id "# The following key should be auto-generated and inserted
    # <#${new_key_1} ${new_text_1}#>
    #
    # The following key should be made unique and inserted
    # <#${new_key_2} ${new_text_2}#>
    #
    # The following key should not be inserted in the message catalog
    # <#${new_key_3} ${new_text_3}#>"
    close $tcl_file_id

    # Write the catalog file
    lang::catalog::export_to_file $catalog_file [array get messages_array]

    # We need to force the API to export to the test catalog file
    aa_stub lang::catalog::get_catalog_file_path "
        return $catalog_file
    "

    # Replace message tags in the tcl file and insert into catalog file
    lang::util::replace_temporary_tags_with_lookups $tcl_file

    aa_unstub lang::catalog::get_catalog_file_path

    # Read the contents of the catalog file
    array set catalog_array [lang::catalog::parse [lang::catalog::read_file $catalog_file]]
    array set updated_messages_array [lindex [array get catalog_array messages] 1]

    # Assert that the old messages are unchanged
    foreach old_message_key [array names messages_array] { 
        aa_true "old key $old_message_key should be unchanged" [string equal $messages_array($old_message_key) \
                                                                             $updated_messages_array($old_message_key)]
    }

    # Check that the first new key was autogenerated
    aa_true "check autogenerated key" [string equal $updated_messages_array(Auto_Key) $new_text_1]

    # Check that the second new key was made unique and inserted
    aa_true "check key made unique" [string equal $updated_messages_array(${new_key_2}_1) $new_text_2]

    # Check that the third key was not inserted    
    aa_true "third key not inserted" [string equal [lindex [array get updated_messages_array $new_key_3] 1] \
                                                   $messages_array($new_key_3)]

    # Check that there are no tags left in the tcl file
    set tcl_file_id [open "[acs_root_dir]/$tcl_file" r]
    set updated_tcl_contents [read $tcl_file_id]
    close $tcl_file_id
    aa_true "tags in tcl file replaced" [expr [llength [lang::util::get_temporary_tags_indices $updated_tcl_contents]] == 0]

    # Delete the test message keys
    foreach message_key [concat [array names messages_array] $expected_new_keys] {
        lang::message::unregister $package_key $message_key
    }
    # Delete the catalog files
    file delete $catalog_backup_file
    file delete $catalog_file

    # Delete the tcl files
    file delete "[acs_root_dir]/$tcl_file"
    file delete "[acs_root_dir]/$tcl_backup_file"
}

aa_register_case util__get_hash_indices {
    Tests the lang::util::get_hash_indices proc

    @author Peter Marklund (peter@collaboraid.biz)
    @creation-date 21 October 2002
} { 
  set multilingual_string "#package1.key1# abc\# #package2.key2#"
  set indices_list [lang::util::get_hash_indices $multilingual_string]
  set expected_indices_list [list [list 0 14] [list 21 35]]

  aa_true "there should be two hash entries" [expr [llength $indices_list] == 2]

  set counter 0
  foreach index_item $indices_list {
      set expected_index_item [lindex $expected_indices_list $counter]
      
      aa_true "checking start and end indices of item $counter" \
              [expr [string equal [lindex $index_item 0] [lindex $expected_index_item 0]] && \
              [string equal [lindex $index_item 1] [lindex $expected_index_item 1]]]

      set counter [expr $counter + 1]
  }
}

aa_register_case util__convert_adp_variables_to_percentage_signs {
    Tests the lang::util::convert_adp_variables_to_percentage_signs proc.

    @author Peter Marklund (peter@collaboraid.biz)
    @creation-date 25 October 2002
} {
    set adp_chunk "<property name=\"title\">@array.variable_name@ @variable_name2@ peter@collaboraid.biz</property>"

    set adp_chunk_converted [lang::util::convert_adp_variables_to_percentage_signs $adp_chunk]
    set adp_chunk_expected "<property name=\"title\">%array.variable_name% %variable_name2% peter@collaboraid.biz</property>"

    aa_true "adp vars should be subsituted with percentage sings" [string equal $adp_chunk_converted \
                                                                                $adp_chunk_expected]

    # Test that a string can start with adp vars
    set adp_chunk "@first_names@ @last_name@&nbsp;peter@collaboraid.biz"
    set adp_chunk_converted [lang::util::convert_adp_variables_to_percentage_signs $adp_chunk]
    set adp_chunk_expected "%first_names% %last_name%&nbsp;peter@collaboraid.biz"
    aa_true "adp vars should be subsituted with percentage sings" [string equal $adp_chunk_converted \
                                                                                $adp_chunk_expected]
}

aa_register_case util__replace_adp_text_with_message_tags {
    Test the lang::util::replace_adp_text_with_message_tags proc.

    @author Peter Marklund (peter@collaboraid.biz)
    @creation-date 28 October 2002
} {
    # File paths used
    set adp_file_path "[lang::test::get_dir]/adp_tmp_file.adp"

    # Write the adp test file
    set adp_file_id [open $adp_file_path w]
    puts $adp_file_id "<master src=\"master\">
<property name=\"title\">@first_names@ @last_name@&nbsp;peter@collaboraid.biz</property>
<property name=\"context_bar\">@context_bar@</property>
Test text"
    close $adp_file_id

    # Do the substitutions
    lang::util::replace_adp_text_with_message_tags $adp_file_path "write"

    # Read the changed test file
    set adp_file_id [open $adp_file_path r]
    set adp_contents [read $adp_file_id]
    close $adp_file_id

    set expected_adp_pattern {<master src=\"master\">
<property name=\"title\"><#[a-zA-Z_]+ @first_names@ @last_name@&nbsp;peter@collaboraid.biz#></property>
<property name=\"context_bar\">@context_bar@</property>
<#[a-zA-Z_]+ Test text\s*}

    # Assert proper replacements have been done
    aa_true "replacing adp text with tags" \
            [regexp $expected_adp_pattern $adp_contents match]

    # Remove the adp test file
    file delete $adp_file_path
}

aa_register_case message__format {
    Tests the lang::message::format proc

    @author Peter Marklund (peter@collaboraid.biz)
    @creation-date 21 October 2002
} {

    set localized_message "The %frog% jumped across the %fence%. About 50% of the time, he stumbled, or maybe it was %%20 %times%."
    set value_list {frog frog fence fence}

    set subst_message [lang::message::format $localized_message $value_list]
    set expected_message "The frog jumped across the fence. About 50% of the time, he stumbled, or maybe it was %20 %times%."

    aa_true "the frog should jump across the fence" [string equal $subst_message \
                                                                  $expected_message]
}

aa_register_case message__get_embedded_vars {
    Tests the lang::message::get_embedded_vars proc

    @author Peter Marklund (peter@collaboraid.biz)
    @creation-date 12 November 2002
} {
    set en_us_message "This message contains no vars"
    set new_message "This is a message with some %vars% and some more %variables%"

    set missing_vars_list [util_get_subset_missing \
            [lang::message::get_embedded_vars $new_message] \
            [lang::message::get_embedded_vars $en_us_message]]

    if { ![aa_true "Find missing vars 'vars' and 'variables'" [util_sets_equal_p $missing_vars_list { vars variables }]] } {
        aa_log "Missing variables returned was: '$missing_vars_list'"
        aa_log "en_US Message: '$en_us_message' -> Variables: '[lang::message::get_embedded_vars $en_us_message]'"
        aa_log "Other Message: '$new_message' -> Variables: '[lang::message::get_embedded_vars $new_message]'"
    }

    # This failed on the test servers
    set en_us_message "Back to %ad_url%%return_url%"
    set new_message "Tillbaka till %ad_url%%return_url%"
    set missing_vars_list [util_get_subset_missing \
            [lang::message::get_embedded_vars $new_message] \
            [lang::message::get_embedded_vars $en_us_message]]
    if { ![aa_equals "No missing vars" [llength $missing_vars_list] 0] } {
        aa_log "Missing vars: $missing_vars_list"
    }

    # Testing variables with digits in the variable names
    set en_us_message "Some variables %var1%%var2% again"
    set new_message "Nogle variable %var1%%var2% igen"
    set missing_vars_list [util_get_subset_missing \
            [lang::message::get_embedded_vars $new_message] \
            [lang::message::get_embedded_vars $en_us_message]]
    if { ![aa_equals "No missing vars" [llength $missing_vars_list] 0] } {
        aa_log "Missing vars: $missing_vars_list"
    }    
}

aa_register_case locale__test_system_package_setting {
    Tests whether the system package level setting works

    @author Lars Pind (lars@collaboraid.biz)
    @creation-date 2003-08-12
} {
    set use_package_level_locales_p_org [parameter::get -parameter UsePackageLevelLocalesP -package_id [apm_package_id_from_key "acs-lang"]]
    
    parameter::set_value -parameter UsePackageLevelLocalesP -package_id [apm_package_id_from_key "acs-lang"] -value 1


    # There's no foreign key constraint on the locales column, so this should work
    set locale_to_set [ad_generate_random_string]

    set retrieved_locale {}
    
    # We could really use a 'finally' block on 'with_catch' (a block, which gets executed at the end, regardless of whether there was an error or not)
    with_catch errmsg {
        # Let's pick a random unmounted package to test with
        set package_id [apm_package_id_from_key "acs-kernel"]
        
        set org_setting [lang::system::site_wide_locale]
        
        lang::system::set_locale -package_id $package_id $locale_to_set
        
        set retrieved_locale [lang::system::locale -package_id $package_id]
        
    } {
        parameter::set_value -parameter UsePackageLevelLocalesP -package_id [apm_package_id_from_key "acs-lang"] -value $use_package_level_locales_p_org
        
        global errorInfo
        error $errmsg $errorInfo
    }

    parameter::set_value -parameter UsePackageLevelLocalesP -package_id [apm_package_id_from_key "acs-lang"] -value $use_package_level_locales_p_org
    
    aa_true "Retrieved system locale ('$retrieved_locale') equals the one we just set ('$locale_to_set')" [string equal $locale_to_set $retrieved_locale]
}

aa_register_case locale__test_lang_conn_browser_locale {
    Tests the proc lang::conn::browser_locale

    @author Peter Marklund
    @creation-date 2003-08-13
} {
    aa_run_with_teardown \
        -rollback \
        -test_code {

        # The tests assume that the danish locale is enabled
        db_dml enable_all_locales {
            update ad_locales
            set enabled_p = 't'
            where locale = 'da_DK'
        }
        util_memoize_flush_regexp {^lang::system::get_locales}

        # First locale is perfect language match
        lang::test::assert_browser_locale "da,en-us;q=0.8,de;q=0.5,es;q=0.3" "da_DK"
    
        # First locale is perfect locale match
        lang::test::assert_browser_locale "da_DK,en-us;q=0.8,de;q=0.5,es;q=0.3" "da_DK"
    
        # Tentative match being discarded
        lang::test::assert_browser_locale "da_BLA,foobar,en" "en_US"
    
        # Tentative match being used
        lang::test::assert_browser_locale "da_BLA,foobar" "da_DK"
    
        # Several tentative matches, all being discarded
        lang::test::assert_browser_locale "da_BLA,foobar,da_BLUB,da_DK" "da_DK"
    }
}


aa_register_case strange_oracle_problem {
    Strange Oracle problem when selecting by language
    
} {
    set language "da "
    set locale da_DK

    set db_string [db_string select_default_locale { 
        select locale 
        from   ad_locales 
        where  language = :language
    } -default "WRONG"]
    
    aa_false "Does not return 'WRONG'" [string equal $db_string "WRONG"]
}


aa_register_case set_get_timezone {
    Test that setting and getting user timezone works
} {
    # We cannot test timezones if they are not installed
    if { [lang::system::timezone_support_p] } {

        # Make sure we have a logged in user
        set org_user_id [ad_conn user_id]

        if { $org_user_id == 0 } {
            set user_id [db_string user { select min(user_id) from users }]
            ad_conn -set user_id $user_id
        } else {
            set user_id $org_user_id
        }

        # Remember originals so we can restore them
        set system_timezone [lang::system::timezone]
        set user_timezone [lang::user::timezone]


        set timezones [lc_list_all_timezones]
        
        set desired_user_timezone [lindex [lindex $timezones [randomRange [expr [llength $timezones]-1]]] 0]
        set desired_system_timezone [lindex [lindex $timezones [randomRange [expr [llength $timezones]-1]]] 0]
        
        set error_p 0
        with_catch errmsg {
            # User timezone
            lang::user::set_timezone $desired_user_timezone
            aa_equals "User timezone retrieved is the same as the one set" [lang::user::timezone] $desired_user_timezone
            
            # Storage
            set user_id [ad_conn user_id]
            aa_equals "User timezone stored in user_preferences table" \
                [db_string user_prefs { select timezone from user_preferences where user_id = :user_id }] \
                $desired_user_timezone
            
            
            # System timezone
            lang::system::set_timezone $desired_system_timezone
            aa_equals "System timezone retrieved is the same as the one set" [lang::system::timezone] $desired_system_timezone
            
            # Connection timezone
            aa_equals "Using user timezone" [lang::conn::timezone] $desired_user_timezone
            
            ad_conn -set isconnected 0
            aa_equals "Fallback to system timezone when no connection" [lang::conn::timezone] $desired_system_timezone
            ad_conn -set isconnected 1

            lang::user::set_timezone {}
            aa_equals "Fallback to system timezone when no user pref" [lang::conn::timezone] $desired_system_timezone

        } {
            set error_p 1
        }
        
        # Clean up
        lang::system::set_timezone $system_timezone
        lang::user::set_timezone $user_timezone
        ad_conn -set user_id $org_user_id

        if { $error_p } {
            # rethrow the error
            global errorInfo
            error $errmsg $errorInfo
        }
    }
}

aa_register_case set_timezone_not_logged_in {
    Test that setting and getting user timezone throws an error when user is not logged in
} {
    # We cannot test timezones if they are not installed
    if { [lang::system::timezone_support_p] } {

        set user_id [ad_conn user_id]

        ad_conn -set user_id 0
        aa_equals "Fallback to system timezone when no user" [lang::conn::timezone] [lang::system::timezone]

        set error_p [catch { lang::user::set_timezone [lang::system::timezone] } errmsg]
        aa_true "Error when setting user timezone when user not logged in" $error_p

        # Reset the user_id 
        ad_conn -set user_id $user_id
    }
}

aa_register_case lc_time_fmt_Z_timezone {
    lc_time_fmt %Z returns current connection timezone
} {
    aa_equals "%Z returns current timezone" [lc_time_fmt "2003-08-15 13:40:00" "%Z"] [lang::conn::timezone]
}

aa_register_case locale_language_fallback {
    Test that we fall back to 'default locale for language' when requesting a message 
    which exists in default locale for language, but not in the current locale
} {
    # Assuming we have en_US and en_GB
    
    set package_key "acs-lang"
    set message_key [ad_generate_random_string]

    set us_message [ad_generate_random_string]
    set gb_message [ad_generate_random_string]
    
    set error_p 0
    with_catch saved_error {
        lang::message::register "en_US" $package_key $message_key $us_message
        
        aa_equals "Looking up message in GB returns US message" \
            [lang::message::lookup "en_GB" "$package_key.$message_key" "NOT FOUND"] \
            $us_message

        lang::message::register "en_GB" $package_key $message_key $gb_message
        
        aa_equals "Looking up message in GB returns GB message" \
            [lang::message::lookup "en_GB" "$package_key.$message_key" "NOT FOUND"] \
            $gb_message
    } {
        set error_p 1
        global errorInfo
        set saved_errorInfo $errorInfo
    }

    # Clean up
    db_dml delete_msg { delete from lang_messages where package_key = :package_key and message_key = :message_key }
    db_dml delete_key { delete from lang_message_keys where package_key = :package_key and message_key = :message_key }

    if { $error_p } {
        error $saved_error $saved_errorInfo
    }
}
