# For documentation, see the ad_library call at the bottom of this script.
set root_directory [file dirname [string trimright [ns_info tcllib] "/"]]
nsv_set acs_properties root_directory $root_directory
catch { nsv_set acs_properties initial_error_log_length [file size [ns_info log]] }

nsv_array set api_proc_doc [list]
nsv_array set api_proc_doc_scripts [list]
nsv_array set api_library_doc [list]
nsv_array set proc_doc [list]
nsv_array set proc_source_file [list]

proc empty_string_p { query_string } {
    return [string equal $query_string ""]
}

proc acs_root_dir {} {
    return [nsv_get acs_properties root_directory]
}

proc acs_package_root_dir { package } {
    return "[acs_root_dir]/packages/$package"
}

proc ad_make_relative_path { path } {
    set root_length [string length [acs_root_dir]]
    if { ![string compare [acs_root_dir] [string range $path 0 [expr { $root_length - 1 }]]] } {
	return [string range $path [expr { $root_length + 1 }] [string length $path]]
    }
    error "$path is not under the path root ([acs_root_dir])"
}

proc ad_parse_documentation_string { doc_string elements_var } {
    upvar $elements_var elements
    if { [info exists elements] } {
        unset elements
    }

    set lines [split $doc_string "\n\r"]

    array set elements [list]
    set current_element main
    set buffer ""

    foreach line $lines {
	
	# lars@pinds.com, 8 July, 2000
	# We don't do a string trim anymore, because it breaks the formatting of 
	# code examples in the documentation, something that we want to encourage.
        
	# set line [string trim $line]

        if { [regexp {^[ \t]*@([-a-zA-Z_]+)(.*)$} $line "" element remainder] } {
            lappend elements($current_element) [string trim $buffer]

            set current_element $element
            set buffer "$remainder\n"
        } else {
            append buffer $line "\n"
        }
    }

    lappend elements($current_element) [string trim $buffer]
}

proc ad_proc args {
    set public_p 0
    set private_p 0
    set deprecated_p 0
    set warn_p 0
    set debug_p 0

    # Loop through args, stopping at the first argument which is
    # not a switch.
    for { set i 0 } { $i < [llength $args] } { incr i } {
        set arg [lindex $args $i]

        # If the argument doesn't begin with a hyphen, break.
        if { [string index $arg 0] != "-" } {
            break
        }

        # If the argument is "--", stop parsing for switches (but
        # bump up $i to the next argument, which is the first
        # argument which is not a switch).
        if { [string equal $arg "--"] } {
            incr i
            break
        }

        switch -- $arg {
            -public { set public_p 1 }
            -private { set private_p 1 }
            -deprecated { set deprecated_p 1 }
            -warn { set warn_p 1 }
            -debug { set debug_p 1 }
            default {
                return -code error "Invalid switch [lindex $args $i] passed to ad_proc"
            }
        }
    }

    if { $public_p && $private_p } {
        return -code error "Mutually exclusive switches -public and -private passed to ad_proc"
    }

    if { $warn_p && !$deprecated_p } {
        return -code error "Switch -warn can be provided to ad_proc only if -deprecated is also provided"
    }

    # Now $i is set to the index of the first non-switch argument.
    # There must be either three or four arguments remaining.
    set n_args_remaining [expr { [llength $args] - $i }]
    if { $n_args_remaining != 3 && $n_args_remaining != 4 } {
        return -code error "Wrong number of arguments passed to ad_proc"
    }

    # Set up the remaining arguments.
    set proc_name [lindex $args $i]
    set arg_list [lindex $args [expr { $i + 1 }]]
    if { $n_args_remaining == 3 } {
        # No doc string provided.
        array set doc_elements [list]
	set doc_elements(main) ""
    } else {
        # Doc string was provided.
        ad_parse_documentation_string [lindex $args end-1] doc_elements
    }
    set code_block [lindex $args end]

    #####
    #
    #  Parse the argument list.
    #
    #####

    set switches [list]
    set positionals [list]
    set seen_positional_with_default_p 0
    set n_positionals_with_defaults 0
    array set default_values [list]
    array set flags [list]
    set varargs_p 0
    set switch_code ""

    # If the first element contains 0 or more than 2 elements, then it must
    # be an old-style ad_proc. Mangle effective_arg_list accordingly.
    if { [llength $arg_list] > 0 } {
        set first_arg [lindex $arg_list 0]
        if { [llength $first_arg] == 0 || [llength $first_arg] > 2 } {
            set new_arg_list [list]
            foreach { switch default_value } $first_arg {
                lappend new_arg_list [list $switch $default_value]
            }
            set arg_list [concat $new_arg_list [lrange $arg_list 1 end]]
        }
    }

    set effective_arg_list $arg_list

    set last_arg [lindex $effective_arg_list end]
    if { [llength $last_arg] == 1 && [string equal [lindex $last_arg 0] "args"] } {
        set varargs_p 1
        set effective_arg_list [lrange $effective_arg_list 0 [expr { [llength $effective_arg_list] - 2 }]]
    }

    set check_code ""
    foreach arg $effective_arg_list {
        if { [llength $arg] == 2 } {
            set default_p 1
            set default_value [lindex $arg 1]
            set arg [lindex $arg 0]
        } else {
            if { [llength $arg] != 1 } {
                return -code error "Invalid element \"$arg\" in argument list"
            }
            set default_p 0
        }

        set arg_flags [list]
        set arg_split [split $arg ":"]
        if { [llength $arg_split] == 2 } {
            set arg [lindex $arg_split 0]
            foreach flag [split [lindex $arg_split 1] ","] {
                if { ![string equal $flag "required"] && ![string equal $flag "boolean"] } {
                    return -code error "Invalid flag \"$flag\""
                }
                lappend arg_flags $flag
            }
        } elseif { [llength $arg_split] != 1 } {
            return -code error "Invalid element \"$arg\" in argument list"
        }

        if { [string equal [string index $arg 0] "-"] } {
            if { [llength $positionals] > 0 } {
                return -code error "Switch -$arg specified after positional parameter"
            }

            set switch_p 1
            set arg [string range $arg 1 end]
            lappend switches $arg

            append switch_code "            -$arg {\n"

            if { [lsearch $arg_flags "boolean"] >= 0 } {
                set default_values(${arg}_p) 0
                append switch_code "                uplevel set ${arg}_p 1\n"
            } else {
                append switch_code "                if { \$i >= \[llength \$args\] - 1 } {
                    return -code error \"No argument to switch -$arg\"
                }
                upvar ${arg} val ; set val \[lindex \$args \[incr i\]\]\n"
            }

            append switch_code "            }\n"
            if { [lsearch $arg_flags "required"] >= 0 } {
                append check_code "    if { !\[uplevel info exists $arg\] } {
        return -code error \"Required switch -$arg not provided\"
    }
"
            }
        } else {
            set switch_p 0
            if { $default_p } {
                incr n_positionals_with_defaults
            }
            if { !$default_p && $n_positionals_with_defaults != 0 } {
                return -code error "Positional parameter $arg needs a default value (since it follows another positional parameter with a default value)"
            }
            lappend positionals $arg
        }

        set flags($arg) $arg_flags

        if { $default_p } {
            set default_values($arg) $default_value
        }

        if { [llength $arg_split] > 2 } {
            return -code error "Invalid format for parameter name: \"$arg\""
        }
    }

    foreach element { public_p private_p deprecated_p warn_p varargs_p arg_list switches positionals } {
        set doc_elements($element) [set $element]
    }
    foreach element { default_values flags } {
        set doc_elements($element) [array get $element]
    }
    
    set root_dir [nsv_get acs_properties root_directory]
    set script [info script]
    set root_length [string length $root_dir]
    if { ![string compare $root_dir [string range $script 0 [expr { $root_length - 1 }]]] } {
        set script [string range $script [expr { $root_length + 1 }] end]
    }
    
    set doc_elements(script) $script
    if { ![nsv_exists api_proc_doc $proc_name] } {
        nsv_lappend api_proc_doc_scripts $script $proc_name
    }

    nsv_set api_proc_doc $proc_name [array get doc_elements]

    # Backward compatibility: set proc_doc and proc_source_file
    nsv_set proc_doc $proc_name [lindex $doc_elements(main) 0]
    if { [nsv_exists proc_source_file $proc_name] \
	    && [string compare [nsv_get proc_source_file $proc_name] [info script]] != 0 } {
        ns_log Notice "Multiple definition of $proc_name in [nsv_get proc_source_file $proc_name] and [info script]"
    }
    nsv_set proc_source_file $proc_name [info script]

    if { [string equal $code_block "-"] } {
        return
    }

    if { [llength $switches] == 0 } {
        proc $proc_name $arg_list $code_block
    } else {
        set parser_code "    upvar args args\n"

        foreach { name value } [array get default_values] {
            append parser_code "    upvar $name val ; set val [list $value]\n"
        }
        
        append parser_code "
    for { set i 0 } { \$i < \[llength \$args\] } { incr i } {
        set arg \[lindex \$args \$i\]
        if { \[string index \$arg 0\] != \"-\" } {
            break
        }
        if { \[string equal \$arg \"--\"\] } {
            incr i
            break
        }
        switch -- \$arg {
$switch_code
            default { return -code error \"Invalid switch: \\\"\$arg\\\"\" }
        }
    }
"

        set n_required_positionals [expr { [llength $positionals] - $n_positionals_with_defaults }]
        append parser_code "
    set n_args_remaining \[expr { \[llength \$args\] - \$i }\]
    if { \$n_args_remaining < $n_required_positionals } {
        return -code error \"No value specified for argument \[lindex { [lrange $positionals 0 [expr { $n_required_positionals - 1 }]] } \$n_args_remaining\]\"
    }
"
        for { set i 0 } { $i < $n_required_positionals } { incr i } {
            append parser_code "    upvar [lindex $positionals $i] val ; set val \[lindex \$args \[expr { \$i + $i }\]\]\n"
        }
        for {} { $i < [llength $positionals] } { incr i } {
            append parser_code "    if { \$n_args_remaining >= [expr { [llength $positionals] - $i }] } {
            upvar [lindex $positionals $i] val ; set val \[lindex \$args \[expr { \$i + $i }\]\]
        }
"
        }
    
        if { $varargs_p } {
            append parser_code "    set args \[lrange \$args \[expr { \$i + [llength $positionals] }\] end\]\n"
        } else {
            append parser_code "
    if { \$n_args_remaining > [llength $positionals] } {
        return -code error \"Too many positional parameters specified\"
    }
    unset args
"
        }

        append parser_code $check_code

        if { $debug_p } {
            ns_write "PARSER CODE:\n\n$parser_code\n\n"
        }
    
        proc __arg_parser_for_$proc_name {} $parser_code
        proc $proc_name args "    __arg_parser_for_$proc_name\n$code_block"
    }
}

ad_proc -deprecated proc_doc { args } {

    A synonym for <code>ad_proc</code> (to support legacy code).
    
} {
    eval ad_proc $args
}

ad_proc -public ad_proc {
    -public:boolean
    -private:boolean
    -deprecated:boolean
    -warn:boolean
    arg_list
    args
} {

    Declares a procedure.

    @param public specifies that the procedure is part of a public API.
    @param private specifies that the procedure is package-private.
    @param deprecated specifies that the procedure should not be used.
    @param warn specifies that the procedure should generate a warning when invoked.
    @param arg_list the list of switches and positional parameters which can be
        provided to the procedure.

} -

ad_proc -public ad_arg_parser { allowed_args argv } {

    Parses an argument list for a database call (switches at the end).
    Switch values are placed in corresponding variable names in the calling
    environment.

    @param allowed_args a list of allowable switch names.
    @param argv a list of command-line options. May end with <code>args</code> to
        indicate that extra values should be tolerated after switches and placed in
        the <code>args</code> list.
    @error if the list of command-line options is not valid.

} {
    if { [string equal [lindex $allowed_args end] "args"] } {
	set varargs_p 1
	set allowed_args [lrange $allowed_args 0 [expr { [llength $allowed_args] - 2 }]]
    } else {
	set varargs_p 0
    }

    if { $varargs_p } {
	upvar args args
	set args [list]
    }

    set counter 0
    foreach { switch value } $argv {
	if { ![string equal [string index $switch 0] "-"] } {
	    if { $varargs_p } {
		set args [lrange $argv $counter end]
		return
	    }
	    return -code error "Expected switch but encountered \"$switch\""
	}
	set switch [string range $switch 1 end]
	if { [lsearch $allowed_args $switch] < 0 } {
	    return -code error "Invalid switch -$switch (expected one of -[join $allowed_args ", -"])"
	}
	upvar $switch switch_var
	set switch_var $value
	incr counter 2
    }
    if { [llength $argv] % 2 != 0 } {
	# The number of arguments has to be even!
	return -code error "Invalid switch syntax - no argument to final switch \"[lindex $argv end]\""
    }
}

ad_proc ad_library {
    doc_string
} {

    Provides documentation for a library (<code>-procs.tcl</code> file).

} {
    ad_parse_documentation_string $doc_string doc_elements
    nsv_set api_library_doc [ad_make_relative_path [info script]] [array get doc_elements]
}

#ad_library {
#
#    Routines for defining procedures and libraries of procedures (<code>-procs.tcl</code>
#    files).
#
#    @creation-date 7 Jun 2000
#    @author Jon Salz (jsalz@mit.edu)
#    @cvs-id 00-proc-procs.tcl,v 1.7.2.3 2000/08/15 22:14:57 ron Exp
#}
