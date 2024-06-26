*! version 2.6.2  03aug2022
*! Sebastian Kripfganz, www.kripfganz.de

*==================================================*
***** postestimation statistics after xtdpdgmm *****

program define xtdpdgmm_estat, rclass
	version 13.0
	if "`e(cmd)'" != "xtdpdgmm" {
		error 301
	}
	gettoken subcmd rest : 0, parse(" ,")
	if "`subcmd'" == substr("serial", 1, max(3, `: length loc subcmd')) {
		loc subcmd			"serial"
	}
	else if "`subcmd'" == substr("overid", 1, max(4, `: length loc subcmd')) {
		loc subcmd			"overid"
	}
	else if "`subcmd'" == substr("hausman", 1, max(4, `: length loc subcmd')) {
		loc subcmd			"hausman"
	}
	else if "`subcmd'" != "serialpm" & "`subcmd'" != "mmsc" {
		loc subcmd			""
	}
	if "`subcmd'" != "" {
		if e(k_aux) > 0 & e(k_aux) < . & inlist("`subcmd'", "serial", "serialpm", "hausman") {
			tempname xtdpdgmm_e
			_est hold `xtdpdgmm_e', copy
			xtdpdgmm_estat_noaux
			cap noi xtdpdgmm_estat_`subcmd' `rest'
			loc error			= _rc
			_est unhold `xtdpdgmm_e'
			if `error' != 0 {
				exit `error'
			}
		}
		else {
			xtdpdgmm_estat_`subcmd' `rest'
		}
	}
	else {
		estat_default `0'
	}
	ret add
end

*==================================================*
**** computation of serial-correlation test statistics ****
program define xtdpdgmm_estat_serial, rclass
	version 13.0
	syntax [, 	Order(numlist int >0)				///
				AR(numlist int >0)]					// historical since version 2.6.1

	if "`ar'" != "" {
		if "`order'" != "" {
			di as err "ar(`ar') invalid"
			exit 198
		}
		loc order			"`ar'"
	}
	else if "`order'" == "" {
		loc order			"1 2"
	}
	tempvar smpl dsmpl e
	qui gen byte `smpl' = e(sample)
	qui predict double `e' if `smpl', e
	tempname b
	mat `b'				= e(b)
	loc indepvars		: coln `b'
	loc indepvars		: subinstr loc indepvars "_cons" "`smpl'", w c(loc constant)
	if !`constant' {
		loc indepvars		: subinstr loc indepvars "o._cons" "o.`smpl'", w c(loc constant)
	}
	loc K				: word count `indepvars'
	tempname score
	forv k = 1 / `K' {
		tempvar `score'`k'
		loc scorevars		"`scorevars' `score'`k'"
		loc var				: word `k' of `indepvars'
		_ms_parse_parts `var'
		if "`r(type)'" != "variable" {
			fvrevar `var'
			loc var				"`r(varlist)'"
		}
		loc dindepvars		"`dindepvars' D.`var'"
	}
	loc sigma2e			= e(sigma2e)
	if `sigma2e' == . {
		qui predict double `score'* if `smpl', score
		cap conf mat e(V_modelbased)
		if !_rc {
			loc V				"e(V_modelbased)"
		}
		else {
			loc V				"e(V)"
		}
	}

	di _n as txt "Arellano-Bond test for autocorrelation of the first-differenced residuals"
	foreach o of num `order' {
		qui gen byte `dsmpl' = `smpl'
		markout `dsmpl' D.`e' L`o'D.`e'
		tsrevar D.`e' if `smpl'
		loc tde				"`r(varlist)'"
		tsrevar L`o'D.`e' if `smpl'
		loc tlde			"`r(varlist)'"
		fvrevar `dindepvars' if `smpl'
		loc tdindepvars		"`r(varlist)'"
		mata: st_numscalar("r(z)", xtdpdgmm_serial("`tde'", "`tlde'", "`tdindepvars'", "`scorevars'", "`_dta[_TSpanel]'", "`e(clustvar)'", "`_dta[_TStvar]'", "`smpl'", "`dsmpl'", "`V'", "e(V)", `sigma2e'))
		loc z`o'			= r(z)
		loc p`o'			= 2 * normal(- abs(`z`o''))
		qui drop `dsmpl'
		di as txt "H0: no autocorrelation of order " `o' _col(40) as txt "z = " as res %9.4f `z`o'' _col(56) as txt "Prob > |z|" _col(68) "=" _col(73) as res %6.4f `p`o''
	}

	foreach o of num `order' {
		ret sca p_`o'		= `p`o''
		ret sca z_`o'		= `z`o''
	}
end

*==================================================*
**** computation of serial-correlation portmanteau test statistics ****
program define xtdpdgmm_estat_serialpm, rclass
	version 13.0
	syntax [, Difference Collapse Order(numlist asc int >0)]

	tempvar smpl dsmpl e
	qui gen byte `smpl' = e(sample)
	qui predict double `e' if `smpl', ue
	tempname b
	mat `b'				= e(b)
	loc indepvars		: coln `b'
	loc indepvars		: subinstr loc indepvars "_cons" "`smpl'", w c(loc constant)
	if !`constant' {
		loc indepvars		: subinstr loc indepvars "o._cons" "o.`smpl'", w c(loc constant)
	}
	loc K				: word count `indepvars'
	tempname score
	forv k = 1 / `K' {
		tempvar `score'`k'
		loc scorevars		"`scorevars' `score'`k'"
	}
	loc sigma2e			= e(sigma2e)
	qui predict double `score'* if `smpl', score
	cap conf mat e(V_modelbased)
	if !_rc {
		loc V				"e(V_modelbased)"
	}
	else {
		loc V				"e(V)"
	}
	if "`difference'" != "" {
		loc difference			"D"
	}
	qui gen byte `dsmpl' = `smpl'
	markout `dsmpl' D.`e'
	sum `_dta[_TStvar]' if `smpl', mean
	loc maxlag			= (r(max) - r(min)) / `_dta[_TSdelta]'
	if "`difference'" != "" {
		loc --maxlag
		loc order1			= 0
	}
	else {
		loc order1			= 1
	}
	if "`order'" == "" {
		loc orderlist		"2 / `maxlag'"
	}
	else {
		loc orderlist			: subinstr loc order " " ",", all
		if max(., `orderlist') > `maxlag' {
			di as err "option order() incorrectly specified -- outside of allowed range"
			exit 125
		}
		if "`difference'" == "" {
			loc order1			: list order1 in order
		}
		else if min(., `orderlist') == 1 {
			di as err "option order() incorrectly specified -- outside of allowed range"
			exit 125
		}
		loc orderlist		: list order - order1
	}
	foreach j of num `orderlist' {
		loc elags			"`elags' L`j'`difference'.`e'"
	}
	if `order1' {
		loc elags			"`elags' F.`e'"
	}
	foreach var of loc indepvars {
		foreach j of num `orderlist' {
			if "`var'" != "`smpl'" {
				fvrevar L`j'`difference'.`var' if `smpl'
				loc indeplags		"`indeplags' `r(varlist)'"
			}
			else {
				loc indeplags		"`indeplags' `smpl'"
			}
		}
		if `order1' {
			if "`var'" != "`smpl'" {
				fvrevar F.`var' if `smpl'
				loc indeplags		"`indeplags' `r(varlist)'"
			}
			else {
				loc indeplags		"`indeplags' `smpl'"
			}
		}
	}
	mata: xtdpdgmm_serialpm(`e(mopt)', "`e'", "`elags'", "`indepvars'", "`indeplags'", "`scorevars'", "`_dta[_TSpanel]'", "`smpl'", "`dsmpl'", "`V'", ("`collapse'" != ""))
	loc chi2			= r(chi2)
	loc df				= r(df)
	loc p				= chi2tail(`df', `chi2')
	if "`difference'`collapse'`order'" == "" {
		di _n as txt "Jochmans" _c
	}
	else {
		di _n as txt "Restricted" _c
	}
	di " portmanteau test" _col(56) "chi2(" as res `df' as txt ")" _col(68) "=" _col(70) as res %9.4f `chi2'
	di as txt "H0: no autocorrelation of " _c
	if "`order'" == "" {
		di "any order" _c
	}
	else if `: word count `orderlist'' == 1 {
		di "order `order'" _c
	}
	else {
		di "specified orders" _c
	}
	di _col(56) "Prob > chi2" _col(68) "=" _col(73) as res %6.4f `p'

	ret sca p			= `p'
	ret sca df			= `df'
	ret sca chi2		= `chi2'
end

*==================================================*
**** computation of overidentification test statistics ****
program define xtdpdgmm_estat_overid, rclass
	version 13.0
	syntax [name(id="estimation results")] , [Difference]

	if "`difference'" != "" & "`namelist'" == "" {
		xtdpdgmm_estat_overid_diff
		ret add
		exit
	}
	loc J				= e(chi2_J)
	loc J_u				= e(chi2_J_u)
	loc df				= e(zrank) + e(zrank_nl) - e(rank)
	loc miss			= 0
	loc miss_u			= 0
	if "`namelist'" == "" {
		di _n as txt "Sargan-Hansen test of the overidentifying restrictions"
		di "H0: overidentifying restrictions are valid"
	}
	else {
		tempname xtdpdgmm_e
		_est hold `xtdpdgmm_e'
		qui est res `namelist'
		if "`e(cmd)'" != "xtdpdgmm" {
			_est unhold `xtdpdgmm_e'
			di as err "`namelist' is not supported by estat overid"
			exit 322
		}
		loc df2				= e(zrank) + e(zrank_nl) - e(rank)
		if `df2' > `df' {
			loc df				= `df2' - `df'
			loc J				= e(chi2_J) - `J'
			loc J_u				= e(chi2_J_u) - `J_u'
		}
		else {
			loc df				= `df' - `df2'
			loc J				= `J' - e(chi2_J)
			loc J_u				= `J_u' - e(chi2_J_u)
		}
		if `df' == 0 | `J' <= 0 {
			loc miss			= 1
		}
		if `df' == 0 | `J_u' <= 0 {
			loc miss_u			= 1
		}
		_est unhold `xtdpdgmm_e'
		di _n as txt "Sargan-Hansen difference test of the overidentifying restrictions"
		di "H0: additional overidentifying restrictions are valid"
	}
	if "`e(estimator)'" == "cugmm" {
		di _n "continuously-updated weighting matrix" _c
	}
	else {
		di _n e(steps) "-step moment functions, " e(steps) "-step weighting matrix" _c
	}
	di _col(56) "chi2(" as res `df' as txt ")" _col(68) "=" _col(70) as res %9.4f `J'
	loc p				= chi2tail(`df', `J')
	if `miss' {
		di as txt "note: assumptions not satisfied" _c
	}
	else if `df' == 0 {
		di as txt "note: coefficients are just-identified" _c
	}
	else if (e(steps) == 1 & "`e(estimator)'" != "cugmm") {
		di as txt "note: *" _c
	}
	di _col(56) as txt "Prob > chi2" _col(68) "=" _col(73) as res %6.4f `p'
	if "`e(estimator)'" != "cugmm" & !("`e(estimator)'" == "igmm" & e(converged)) {
		di _n as txt e(steps) "-step moment functions, " e(steps) + 1 "-step weighting matrix" _col(56) "chi2(" as res `df' as txt ")" _col(68) "=" _col(70) as res %9.4f `J_u'
		loc p_u				= chi2tail(`df', `J_u')
		if `miss_u' {
			di as txt "note: assumptions not satisfied" _c
		}
		else if `df' == 0 {
			di as txt "note: coefficients are just-identified" _c
		}
		else if (e(steps) == 1) {
			di as txt "note: *" _c
		}
		di _col(56) as txt "Prob > chi2" _col(68) "=" _col(73) as res %6.4f `p_u'
	}
	if e(steps) == 1 & `df' & (!`miss' | !`miss_u') & "`e(estimator)'" != "cugmm" {
		di _n as txt "* asymptotically invalid if the one-step weighting matrix is not optimal"
	}

	if "`e(estimator)'" != "cugmm" & !("`e(estimator)'" == "igmm" & e(converged)) {
		ret sca p_J_u		= `p_u'
		ret sca chi2_J_u	= `J_u'
	}
	ret sca p_J			= `p'
	ret sca df_J		= `df'
	ret sca chi2_J		= `J'
end

*==================================================*
**** computation of overidentification difference test statistics ****
program define xtdpdgmm_estat_overid_diff, rclass
	version 13.0

	capture conf mat e(J)
	if _rc {
		error 321
	}
	di _n as txt "Sargan-Hansen (difference) test of the overidentifying restrictions"
	di "H0: (additional) overidentifying restrictions are valid"
	if "`e(estimator)'" == "cugmm" {
		di _n "continuously-updated weighting matrix from full model"
	}
	else {
		di _n e(steps) "-step weighting matrix from full model"
		if e(steps) == 1 {
			di "note: asymptotically invalid if the one-step weighting matrix is not optimal"
		}
	}

	loc iveqnames		: cole e(W), q
	loc ivnames			: coln e(W)
	loc j				= 0
	loc df_nl			= 0
	loc model_nl		"nl"
	forv k = 1 / `= e(zrank) + e(zrank_nl)' {
		loc iveqname		: word `k' of `iveqnames'
		gettoken ivset iveqname : iveqname
		if "`ivset'" == "nl" {
			gettoken model_nl : iveqname
			loc ++df_nl
		}
		else if `ivset' > `j' {
			gettoken model_`ivset' : iveqname
			if "`model_`ivset''" == "iid" {
				loc ++df_nl
			}
			else {
				loc ivsets			"`ivsets' `ivset'"
				loc df_`ivset'		= 1
				loc cons_`ivset'	= ("`: word `k' of `ivnames''" == "_cons")
			}
			loc j				= `ivset'
		}
		else {
			if "`model_`ivset''" == "iid" {
				loc ++df_nl
			}
			else {
				loc ++df_`ivset'
			}
		}
	}
	tempname J J_r
	mat `J'				= e(J)
	loc g				= 1
	loc G				= colsof(`J')
	loc df_diff			= 0
	loc df_fodev		= 0
	loc df_iid			= 0
	loc df_mdev			= 0
	loc df_level		= 0
	foreach ivset of loc ivsets {
		if !`cons_`ivset'' {
			loc df_`model_`ivset''	= `df_`model_`ivset''' + `df_`ivset''
		}
		if el(`J', 3, `g') == `ivset' {
			loc chi2			= el(`J', 1, `g')
			loc df				= e(zrank) + e(zrank_nl) - `df_`ivset'' - e(rank)
			loc df_r			= el(`J', 2, `g')
			if `df' < `df_r' & `df_r' < . {
				loc df_`ivset'		= `df_`ivset'' + `df' - `df_r'
				loc df				= `df_r'
			}
			loc chi2_d			= e(chi2_J) - `chi2'
			if `df' < 0	{
				loc df_`ivset'		= .
			}
			mat `J_r'			= (nullmat(`J_r') \ (`chi2', `df', chi2tail(`df', `chi2'), `chi2_d', `df_`ivset'', chi2tail(`df_`ivset'', `chi2_d')))
			loc rnames			`"`rnames' "`ivset', model(`model_`ivset'')""'
			loc rspec			"`rspec'&"
			loc ++g
		}
	}
	while `g' <= `G' {
		if el(`J', 3, `g') == .d {
			loc model			"diff"
		}
		else if el(`J', 3, `g') == .f {
			loc model			"fodev"
		}
		else if el(`J', 3, `g') == .m {
			loc model			"mdev"
		}
		else if el(`J', 3, `g') == .a {
			loc model			"mean"
		}
		else if el(`J', 3, `g') == .z {
			loc model			"level"
		}
		else if el(`J', 3, `g') == .n {
			loc model			"nl"
		}
		loc chi2			= el(`J', 1, `g')
		loc df				= e(zrank) + e(zrank_nl) - `df_`model'' - e(rank)
		loc chi2_d			= e(chi2_J) - `chi2'
		if `df' < 0	{
			loc df_`model'		= .
		}
		mat `J_r'			= (`J_r' \ (`chi2', `df', chi2tail(`df', `chi2'), `chi2_d', `df_`model'', chi2tail(`df_`model'', `chi2_d')))
		if "`model'" == "nl" {
			loc rnames			"`rnames' nl(`model_nl')"
		}
		else {
			loc rnames			"`rnames' model(`model')"
		}
		loc rspec			"`rspec'&"
		loc ++g
	}
	mat cole `J_r'		= Excluding Excluding Excluding Difference Difference Difference
	mat coln `J_r'		= chi2 df p chi2 df p
	mat rown `J_r'		= `rnames'
	matlist `J_r', cspec(& %17s | %10.4f & %5.0f & %8.4f | %11.4f & %5.0f & %8.4f &) rspec(&|`rspec') row("Moment conditions")

	ret mat J			= `J_r'
end

*==================================================*
**** computation of generalized Hausman test statistic ****
program define xtdpdgmm_estat_hausman, rclass
	version 13.0
	syntax anything(id="estimation results") , [DF(integer 0) noNEsted]
	gettoken estname anything : anything , match(paren) bind
	if `: word count `estname'' != 1 | `"`paren'"' != "" {
		error 198
	}
	gettoken varlist anything : anything, match(paren) bind
 	if (`"`paren'"' == "" & `"`varlist'"' != "") | (`"`paren'"' != "" & `"`anything'"' != "") {
		error 198
	}
	if `df' < 0 {
		di as err "option df() incorrectly specified -- outside of allowed range"
		exit 198
	}
	if "`nested'" != "" & `df' > 0 {
		di as err "options df() and nonested may not be combined"
		exit 184
	}

	forv e = 1 / 2 {
		loc clustvar`e'		"`e(clustvar)'"
		if `e' == 2 {
			tempname xtdpdgmm_e
			_est hold `xtdpdgmm_e'
			qui est res `estname'
			if "`e(cmd)'" != "xtdpdgmm" {
				_est unhold `xtdpdgmm_e'
				di as err "`estname' is not supported by estat hausman"
				exit 322
			}
			if "`clustvar1'" != "`clustvar2'" {
				_est unhold `xtdpdgmm_e'
				di as err "cannot compare estimates based on different cluster variables"
				exit 322
			}
			if e(k_aux) > 0 & e(k_aux) < . {
				xtdpdgmm_estat_noaux
			}
		}
		tempname b`e'
		mat `b`e''			= e(b)
		loc bvars`e'		: coln `b`e''
		if `e' == 1 {
			if `"`varlist'"' == "" {
				loc cons			"_cons o._cons"
				loc varlist			: list bvars`e' - cons
			}
			else {
				fvexpand `varlist'
				loc varlist			"`r(varlist)'"
			}
			if `df' > `: word count `varlist'' {
				di as err "option df() incorrectly specified -- outside of allowed range"
				exit 198
			}
			tempvar touse
			qui gen byte `touse' = e(sample)
		}
		else {
			tempvar aux
			qui gen byte `aux' = e(sample)
			qui replace `aux' = `aux' - `touse'
			sum `aux', mean
			if r(max) | r(min) {
				_est unhold `xtdpdgmm_e'
				di as err "estimation samples must coincide"
				exit 322
			}
			drop `aux'
		}
		if !`: list varlist in bvars`e'' {
			if `e' == 2 {
				_est unhold `xtdpdgmm_e'
			}
			di as err "`: list varlist - bvars`e'' not found"
			exit 111
		}
		tempname score`e'
		forv k = 1 / `: word count `bvars`e''' {
			tempvar `score`e''`k'
			loc scorevars`e' "`scorevars`e'' `score`e''`k'"
		}
		qui predict double `score`e''* if `touse', score
		tempname V`e'
		cap conf mat e(V_modelbased)
		if !_rc {
			mat `V`e''			= e(V_modelbased)
		}
		else {
			mat `V`e''			= e(V)
		}
		tempname pos`e' aux
		foreach var of loc varlist {
			loc k				: list posof "`var'" in bvars`e'
			mat `pos`e''		= (nullmat(`pos`e''), `k')
			mat `aux'			= (nullmat(`aux'), `b`e''[1, "`var'"])
		}
		mat `b`e''			= `aux'
		if `df' == 0 {
			loc df`e'			= e(zrank) + e(zrank_nl) - e(rank)
		}
	}
	_est unhold `xtdpdgmm_e'

	mata: xtdpdgmm_hausman(	"`scorevars1'",			///
							"`scorevars2'",			///
							"`_dta[_TSpanel]'",		///
							"`clustvar1'",			///
							"`_dta[_TStvar]'",		///
							"`touse'",				///
							"`b1'",					///
							"`b2'",					///
							"`pos1'",				///
							"`pos2'",				///
							"`V1'",					///
							"`V2'")
	loc chi2			= r(chi2)
	if `df' == 0 & "`nested'" == "" {
		loc df				= min(abs(`df1' - `df2'), r(df_max))
	}
	else if "`nested'" != "" {
		loc df				= r(df_max)
	}
	loc p				= chi2tail(`df', `chi2')
	di _n as txt "Generalized Hausman test" _col(56) "chi2(" as res `df' as txt ")" _col(68) "=" _col(70) as res %9.4f `chi2'
	di as txt "H0: coefficients do not systematically differ" _col(56) "Prob > chi2" _col(68) "=" _col(73) as res %6.4f `p'

	ret sca p			= `p'
	ret sca df			= `df'
	ret sca chi2		= `chi2'
end

*==================================================*
**** computation of Andrews-Lu MMSC statistics ****
program define xtdpdgmm_estat_mmsc, rclass
	version 13.0
	syntax [namelist(id="estimation results")] , [N(str) HQ(real 1.01)]

	if `hq' <= 1 {
		di as txt "note: HQ factor must be larger than 1 for consistency of MMSC-HQIC"
	}
	if "`n'" == "" {
		loc n				= cond(e(N_clust) != e(N_g) & e(N_clust) < ., "N_clust", "N_g")
	}
	else if "`n'" == substr("groups", 1, max(2, `: length loc n')) {
		loc n				"N_g"
	}
	else if "`n'" == substr("cluster", 1, max(2, `: length loc n')) {
		loc n				= cond(e(N_clust) < ., "N_clust", "N_g")
	}
	else if "`n'" == "obs" {
		loc n				"N"
	}
	else {
		di as err "option n() incorrectly specified"
		exit 198
	}
	loc ngroups			= e(`n')
	loc J				= e(chi2_J)
	loc nmom			= e(zrank) + e(zrank_nl)
	loc npar			= e(rank)
	loc m				: word count `namelist'
	if `m' > 0 {
		forv e = 1 / `m' {
			loc name 			: word `e' of `namelist'
			tempname xtdpdgmm_e
			_est hold `xtdpdgmm_e'
			qui est res `name'
			if "`e(cmd)'" != "xtdpdgmm" {
				_est unhold `xtdpdgmm_e'
				di as err "`name' is not supported by estat mmsc"
				exit 322
			}
			loc ngroups`e'		= e(`n')
			if `ngroups`e'' >= . {
				di as err "cluster-robust results not found for estimation results `name'"
				exit 322
			}
			loc J`e'			= e(chi2_J)
			loc nmom`e'			= e(zrank) + e(zrank_nl)
			loc npar`e'			= e(rank)
			_est unhold `xtdpdgmm_e'
		}
	}

	di _n as txt "Andrews-Lu model and moment selection criteria"
	tempname S
	mat `S'				= (`ngroups', `J', `nmom', `npar', `J' - 2 * (`nmom' - `npar'), `J' - (`nmom' - `npar') * ln(`ngroups'), `J' - 2 * `hq' * (`nmom' - `npar') * ln(ln(`ngroups')))
	if `m' > 0 {
		forv e = 1 / `m' {
			mat `S'				= (`S' \ `ngroups`e'', `J`e'', `nmom`e'', `npar`e'', `J`e'' - 2 * (`nmom`e'' - `npar`e''), `J`e'' - (`nmom`e'' - `npar`e'') * ln(`ngroups`e''), `J`e'' - 2 * `hq' * (`nmom`e'' - `npar`e'') * ln(ln(`ngroups`e'')))
			loc rspec			"`rspec'&"
		}
	}
	mat coln `S' = N J nmom npar MMSC-AIC MMSC-BIC MMSC-HQIC
	mat rown `S' = . `namelist'
	matlist `S', cspec(& %12s | %7.0f & %9.4f & %4.0f & %4.0f & %9.4f & %9.4f & %9.4f &) rspec(&|&`rspec') row("Model")
	di _n as txt "note: MMSC-BIC and MMSC-HQIC use N = e(`n')"

	ret mat S			= `S'
end

*==================================================*
**** repost estimates not in auxiliary form ****
program define xtdpdgmm_estat_noaux, eclass
	version 13.0

	tempname b
	mat `b'				= e(b)
	loc regnames		: coleq `b'
	mat coleq `b'		= ""
	mat coln `b'		= `regnames'
	eret repost b = `b', rename
	eret sca k_aux		= 0
	cap conf mat e(V_modelbased)
	if !_rc {
		tempname V0
		mat `V0'			= e(V_modelbased)
		mat roweq `V0'		= ""
		mat coleq `V0'		= ""
		mat rown `V0'		= `regnames'
		mat coln `V0'		= `regnames'
		eret mat V_modelbased = `V0'
	}
end
