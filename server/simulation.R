output$termcriteriadiv <- renderUI({
    method <- input$terminationcriteria
    if (is.null(method)) {
        return(NULL)
    }

    textInput("termcriteriavalue", "Value of termination criteria", value=method)
})


output$individualhorizon <- renderUI({
    if (have_age()) {
        checkboxInput("agelimit", "Terminate patient at 100", value=TRUE)
    } else {
        HTML("No <code>age</code> attribute provided either in the uploaded data or as a simulated attribute.")
    }
})

output$simendstates <- renderUI({
    res <- simoutput()
    
    if (is.null(res))
        return(NULL)

    isolate({

        withProgress(message="Summarising simulation...", value=0.3, {

            termination_method <- input$terminationcriteria
            this_states <- c(states(), "oldage")

             if (termination_method == "Time limit") {
                 censor_time <- as.numeric(input$termcriteriavalue)
                 res <- res[ time < censor_time]
             }

            end_states_table <- table(res[res[, .I[time == max(time)], by=c("simulation", "id")]$V1]$state)
            end_states_table <- end_states_table / sum(end_states_table)
            
            corrected_missing <- sapply(seq(length(this_states)), function(state) {
                if (is.na(end_states_table[state])) 0 else end_states_table[state] 
            })
            item_list <- list(h4("Average state occupancy"),
                              renderTable(data.frame(State=this_states, `Occupancy (pct)`=corrected_missing*100))
            )
            do.call(tagList, item_list)
        })
    })
})

output$savebuttons <- renderUI({
    res <- simoutput()

    if (is.null(res))
        return(NULL)

    fluidRow(
        hr(),
        textInput("simulationname", "Simulation name"),
        downloadButton("savemodel", "Save model"),
        downloadButton("saveresults", "Save results")
    )
})

output$savemodel <- downloadHandler(
    filename = function() {
        paste0(input$simulationname, '_model.json')
    },
    content = function(file) {
        this_states = states()
        this_transitions = reactiveValuesToList(transitions)

        if (!is.null(input$agelimit) && input$agelimit) {
            oldage_ind <- length(this_states) + 1
            for (i in seq_along(this_states)) {
                this_transitions[[paste(i, oldage_ind, sep='-')]] <- list(dist="Oldage", params="[age]*365.25",
                                                                          to=oldage_ind, from=i)
            }
            this_states <- c(this_states, DEATH_OLD_AGE_STATE)
        }

        output <- list(
           'transitions' = lapply(this_transitions, function(t) {
                   list('source' = this_states[t$from],
                        'target' = this_states[t$to],
                        'distribution' = t$dist,
                        'parameters' = t$params)
                        }),
           'states' = this_states,
           'simulation_parameters' = list('termination_criteria'=input$terminationcriteria,
                                          'termination_value'=input$termcriteriavalue,
                                          'entry_rate'=input$entryrate)
        )
        write(toJSON(output, pretty=T), file)
    }
)

# This method currently only produces wide formatted CSVs, where each state is either visited or not.
# This doesn't allow for recurrent visits to states, even though my DES model allows this to happen.
# I should really change the output of the DES to better reflect this, rather than forcing it into the
# wide mstate CSV method.
#
# Maybe just return a long data frame with a row referring to a transitions with the following columns:
#   - sim number
#   - individual number
#   - time
#   - start state
#   - end state
#
# I could then write wrappers to convert it to mstate style wide tables, or long mstate transition tables
# But essentially, since there are so many possibilities of what the user would want to do with the
# simulation results, it's probably better to provide it as raw as possible and let them do the manual
# tweaking to obtain the required format for their specific analysis
output$saveresults <- downloadHandler(
    filename = function() {
        paste0(input$simulationname, '_results.csv')
    },

    content = function(file) {

        withProgress(message="Collating results", value=0.3, {

            # Setup vars needed
            res <- simoutput()
            n_sims <- length(res)
            this_states <- states()
            this_sinks <- sink_states()

            # Add death from old age if using
            if (!is.null(input$agelimit) && input$agelimit) {
                this_states <- c(this_states, DEATH_OLD_AGE_STATE)
                this_sinks <- c(this_sinks, DEATH_OLD_AGE_STATE)
            }

            resDT <- rbindlist(res, idcol='sim')
            resDT$state <- this_states[resDT$state+1]

            covars <- names(resDT)[!names(resDT) %in% c('sim', 'id', 'state', 'time')]
            id_cols <- c('id', 'sim', covars)
            melt_form <- as.formula(paste(paste(id_cols, collapse='+'), 'state', sep='~'))
            termination_method <- input$terminationcriteria
            termination_value <- as.numeric(input$termcriteriavalue)
            censor_time <- if (termination_method == "Time limit") termination_value else max(resDT$time)

            # Cast to wide to get state-specific times, required to get NAs for states that aren't entered
            resDT_wide <- dcast(resDT, melt_form, value.var='time')
            # Add status, this is done melting back to long
            resDT_long <- melt(resDT_wide, id.vars=id_cols,
                               measure.vars=this_states, variable.name="state", value.name="time")
            resDT_long[, status := as.numeric(!is.na(time))]

            # Censor any observations above censor time
            resDT_long[time > censor_time, c("time", "status") := list(censor_time, 0)]

            # Cast back to wide
            resDT_complete <- dcast(resDT_long, melt_form, value.var=c("time", "status"))

            # Final step is to add in censored times for states that aren't reached
            time_cols <- grep("time_", colnames(resDT_complete))
            time_names <- colnames(resDT_complete)[time_cols]
            sink_cols <- which(colnames(resDT_complete) %in% paste0("status_", this_sinks))

            missing_time <- resDT_complete[, Reduce(`|`, lapply(.SD, function(x) is.na(x))), .SDcols=time_cols]
            reached_absorbtive_state <- resDT_complete[, Reduce(`|`, lapply(.SD, function(x) x == 1)), .SDcols=sink_cols] >= 1

            for (i in time_names) {
                # Set non-absorbed observations to censor time
                resDT_complete[!reached_absorbtive_state & is.na(get(i)), (i) := censor_time]

                # Set observations that reached sink state to time at entry of sink state
                resDT_complete[reached_absorbtive_state & is.na(get(i)), (i) := rowMaxs(as.matrix(.SD), na.rm=T), .SDcols=time_names]
            }

            setorder(resDT_complete, sim, id)
            write.csv(resDT_complete, file, quote=F, row.names = F)
        })
    }
)

simoutput <- eventReactive(input$runmultiplesimbutton, {
    n_sims <- input$simslider
    platform <- .Platform$OS.type

    # Put this in function somewhere?
    # Guard inputs
    entry_rate <- tryCatch(as.numeric(input$entryrate),
                           warning=function(w) {
                                 message("Error: Please provide a numeric value for entry rate.")
                                 return(NULL)
                          })
    termination_value <- tryCatch(as.numeric(input$termcriteriavalue),
                                  warning=function(w) {
                                     message("Error: Please provide a numeric value for termination criteria.")
                                     return(NULL)
                             })
    termination_method <- input$terminationcriteria
    if (is.null(entry_rate) || is.null(termination_value))
        return()

    # Raw number of individuals
    num_inds <- calculate_number_individuals(entry_rate, termination_method, termination_value)
    censor_time <- if (termination_method == "Time limit") termination_value else NULL

    # Setup transition matrix
    trans_mat <- Q()
    transition_list <- reactiveValuesToList(transitions)
    attrs <- reactiveValuesToList(attributes)

    # Extract vector of attributes with categorical variables being expanded to
    # include the dummy variable for each level
    attr_names <- c('intercept', unlist(lapply(names(attrs), function(a) {
        attr <- attrs[[a]]
        if (attr$type == "Categorical") {
            paste(a, attr$levels, sep='.')
        } else if (attr$type == 'Continuous') {
            a
        } else {
            stop(paste0("Error: Unknown data type '", attr$type, "'."))
        }
    })))
    age_limit <- if (!is.null(input$agelimit) && input$agelimit) 100 else FALSE

    withProgress(message="Running simulations...", {
        end_states <- run_simulation_cpp(trans_mat, num_inds, entry_rate, censor_time,
                           attrs, lapply(transition_list, function(x) x$model),
                           n_sims, age_limit)
    })

    end_states
})