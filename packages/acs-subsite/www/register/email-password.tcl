ad_page_contract {
    Sends the user their password.  Depending on the configuration,
    this password may be a new random password.

    @version $Id$
} -query {
    user_id:integer,notnull
} -properties {
    user_id:onevalue
    question_answer_p:onevalue
    password_question:onevalue
}

if {![ad_parameter EmailForgottenPasswordP security 1]} {
    ad_return_error "Feature disabled" "This feature is disabled on this server."
    return
}

if {![ad_parameter "RequireQuestionForPasswordResetP"]} {
    ad_returnredirect "./email-password-2?user_id=$user_id&validated_p=1"
    ad_script_abort
}

set password_question [db_string select_question {} -default ""]

if {[empty_string_p $password_question]} {
    set question_answer_p 0
} else {
    set question_answer_p 1
}

ad_return_template
