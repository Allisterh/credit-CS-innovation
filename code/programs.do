program import_data

    args USPTO PatentsView

    /*****************
    Import US Patent data. The downside to unzipping files in Stata is that I can only unzip to the current
    directory. I hope this changes in the future!
    *****************/
    if `USPTO' {
        cd $data
        unzipfile "https://bulkdata.uspto.gov/data/patent/assignment/economics/2022/dta.zip", replace
        cd $code
    }

    * Import the Patentsview data
    if `PatentsView' {
        cd $data
        unzipfile "https://s3.amazonaws.com/data.patentsview.org/download/g_patent.tsv.zip", replace
        unzipfile "https://s3.amazonaws.com/data.patentsview.org/download/g_location_disambiguated.tsv.zip", replace
        unzipfile "https://s3.amazonaws.com/data.patentsview.org/download/g_assignee_disambiguated.tsv.zip", replace
        cd $code
    }
end

program generate_dtas_patentsview

    /* 
    The USPTO data is large. So I am going to load it chunks and merge the chunks.

    You will need xframeappend and chunky installed:
    > ssc install xframeappend
    > ssc install chunky
    */
    args YesOrNo
    loc chunksize 0.2 GB
    
    if `YesOrNo' {

        chunky using "$data/g_patent.tsv", replace chunksize(`chunksize') header(include) ///
        stub("$data/g_patent_chunk")

        chunky using "$data/g_inventor_disambiguated.tsv", replace chunksize(`chunksize') head(include) ///
        stub("$data/g_inventor_chunk")

        /* 
        Now, for every inventor file, loop through every patent file, exectuting a merge at each step. To analyze
        the success of the total merge, I need to save the number of matches at each loop and keep a running
        tally.
        */
        
        clear frames                  // Resetting the frames memory
        loc matched = 0
        loc inventor_files: dir "$data" files "g_inventor_chunk*"
        loc patent_files: dir "$data" files "g_patent_chunk*"
        frame create chunk
        foreach inventor_file in `inventor_files' {

            frame chunk {

                import delimited "$data/`inventor_file'", clear varnames(1)

                foreach patent_file in `patent_files' {

                    merge m:1 patent_id using "$data/`patent_file'", keep(1 3)
                    qui summ _merge if _merge == 3
                    loc mathced = `matched' + `r(N)'
                    drop _merge
                }
            }

            xframeappend chunk, fast
            di "Appended `inventor_file'"
        }
        
    }
end

program generate_dta_census

    args YesOrNo
    
    if `YesOrNo' {
        * Census business dynamics
        import delimited "$data/BDSTIMESERIES-BDSGEO-Data.csv", clear
        cap drop v32                                                // Random empty column at the end?

        * The first row are varnames and the second are  the corresponding labels. Let's clean this up a bit
        ds
        loc varcount: word count `r(varlist)'
        di `varcount'
        foreach i of numlist 1/`varcount' {

            loc varname = v`i'[1]
            loc varlab  = v`i'[2]
            
            
            ren v`i' `varname'
            lab var `varname' "`varlab'"

        }
        keep if _n > 2                                              // No longer need these

        * Now let's fix the data types
        ds GEO_ID NAME NAICS NAICS_LABEL METRO METRO_LABEL, not
        foreach i in `r(varlist)' {
            destring `i', replace force
        }
        keep if NAICS == "00"                                       // Keep only the all industry totals
        drop if NAME == "District of Columbia"                      // My other data do not include
        save "$data/census-clean.dta", replace
    }

end