ad_proc search_indexer {} {
    @author Neophytos Demetriou
} {

    set driver [ad_parameter -package_id [apm_package_id_from_key search] FtsEngineDriver]

    db_foreach search_observer_queue_entry {
	select object_id, date, event
	from search_observer_queue
	order by date asc
    } {
	
	switch $event {
	    INSERT {
		set object_type [db_exec_plsql get_object_type "select acs_object_util__get_object_type($object_id)"]
		array set datasource [acs_sc_call FtsContentProvider datasource [list $object_id] $object_type]
		set txt [search_content_filter $datasource(content) $datasource(mime) $datasource(storage)]
		acs_sc_call FtsEngineDriver index [list $datasource(object_id) $txt $datasource(title) $datasource(keywords)] $driver
	    } 
	    DELETE {
		acs_sc_call FtsEngineDriver unindex [list $object_id] $driver
	    } 
	    UPDATE {
		set object_type [db_exec_plsql get_object_type "select acs_object_util__get_object_type($object_id)"]
		array set datasource [acs_sc_call FtsContentProvider datasource [list $object_id] $object_type] 
		set txt [search_content_filter $datasource(content) $datasource(mime) $datasource(storage)]
		if { $txt != "" } {
		    acs_sc_call FtsEngineDriver update_index [list $datasource(object_id) $txt $datasource(title) $datasource(keywords)] $driver
		}
	    }
	}

	db_exec_plsql search_observer_dequeue_entry {
	    select search_observer__dequeue(
	        :object_id,
	        :date,
	        :event
	    );
	}
    }
}



ad_proc search_content_filter {
    content
    mime
    storage
} {
    @author Neophytos Demetriou
} {
    switch $mime {
	{text/plain} {
	    return $content 
	}
	{text/html} {
	    return $content
	}
    }
    return
}


ad_proc search_content_get {
    content
    mime
    storage
} {
    @author Neophytos Demetriou

    @param content 
    holds the filename if storage=file
    holds the text data if storage=text
    holds the lob_id if storage=lob
} {
    switch $storage {
	text {
	    return $content
	}
	file {
	    if {[file exists $content]} {
		set ofp [open $content r]
		set txt [read $ofp]
		close $ofp
	    } else {
		error "file: $content doesn't exist"
	    }
	    return [DoubleApos $txt]
	}
	lob {
	    return $txt
	}
    }
    return
}



ad_proc search_choice_bar { items links values {default ""} } {
    @author Neophytos Demetriou
} {

    set count 0
    set return_list [list]

    foreach value $values {
        if { [string compare $default $value] == 0 } {
                lappend return_list "<font color=a90a08><strong>[lindex $items $count]</strong></font>"
        } else {
                lappend return_list "<a href=\"[lindex $links $count]\"><font color=000000>[lindex $items $count]</font></a>"
        }

        incr count
    }

    if { [llength $return_list] > 0 } {
        return "[join $return_list " "]"
    } else {
        return ""
    }
    
}




