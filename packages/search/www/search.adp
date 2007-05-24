<master>
<property name="header_stuff">
  <link href="/resources/search/search.css" rel="stylesheet" type="text/css">
</property>
<if @link:rowcount@ not nil><property name="&link">link</property></if>

<if @empty_p@ true>
    <p class="hint">#search.lt_You_must_specify_some#</p>
</if>
<else>
	<if @and_queries_notice_p@ eq 1>
      	  <font color="6f6f6f">
          #search.The#
          [<a href=help/basics#and>#search.details#</a>]<br>
        </font>
	</if>
	<if @nstopwords@ eq 1>
        <font color="6f6f6f">
          #search.lt_bstopwordsb_is_a_very#
          [<a href=help/basics#stopwords>#search.details#</a>]<br>
        </font>
	</if>
	<if @nstopwords@ gt 1>
      	  <font color="6f6f6f">
          #search.lt_The_following_words_a# <b>@stopwords@</b>.
          [<a href=help/basics#stopwords>#search.details#</a>]<br>
      	  </font>
	</if>

  <if @count@ eq 0>
  Your search - <b>@query@</b> - did not match any content.
  <br>#search.lt_No_pages_were_found_c#<b>@query@</b>".
  <br><br>#search.Suggestions#
  <ul>
    <li>#search.lt_Make_sure_all_words_a#
    <li>#search.lt_Try_different_keyword#
    <li>#search.lt_Try_more_general_keyw#
    <if @nquery@ gt 2>
      <li>#search.Try_fewer_keywords#
    </if>
  </ul>
  </if>
  <else>
        <div id="search-info">
          <p class="subtitle">#search.Searched_for_query#</p>
          <p class="times">
        #search.Results# <strong>@low@-@high@</strong> #search.of_about# <strong>@count@</strong>#search.________Search_took# <strong>@elapsed@</strong> #search.seconds# 
          </p>
        </div>
        <div id="search-results">
          <ol start="@ol_start@">
            <multiple name="searchresult">
              <li>
                <div>
                  <a href="@searchresult.url_one@" class="result-title">
                    <if @searchresult.title_summary@ nil>#search.Untitled#</if>	
                    <else>@searchresult.title_summary;noquote@</else>
                  </a>
                </div>
                <if @searchresult.txt_summary@ not nil>	
                  <div>@searchresult.txt_summary;noquote@</div>
                </if>
                <div class="result-url">@searchresult.url_one@</div>
              </li>
            </multiple>
          </ol>
        </div>
  </else>


<if @from_result_page@ lt @to_result_page@>
  <div id="results-pages">

    #search.Result_page#

    <if @from_result_page@ lt @current_result_page@>
      <a href="@url_previous@"><b>#search.Previous#</b></a>
    </if>
    &nbsp;@choice_bar;noquote@&nbsp;
    
    <if @current_result_page@ lt @to_result_page@>
	<a href="@url_next@"><b>#search.Next#</b></a>
    </if>
  </div>
</if>
<if @count@ gt 0>
  <center>
    <div>
      <form method="get" action="search">
        <input type="text" name="q" size="60" maxlength="256" value="@query@" />
        <input type="submit" value="#search.Search#" />
      </form>
      <if @t@ eq "Search">
        <i>#search.lt_Tip_In_most_browsers_#</i>
      </if>
    </div>

    <if @stw@ not nil>
      <p><font size=-1>#search.lt_Try_your_query_on_stw#</font></p>
    </if>
  </center>
</if>
</else>

    <if @and_queries_notice_p@ eq 1>
      <p class="hint">#search.and_not_needed# [<a href="help/basics#and">#search.details#</a>]</p>
    </if>
    <if @nstopwords@ eq 1>
      <p class="hint">#search.lt_bstopwordsb_is_a_very# [<a href="help/basics#stopwords">#search.details#</a>]</p>
    </if>
    <if @nstopwords@ gt 1>
      <p class="hint">#search.lt_The_following_words_a# [<a href="help/basics#stopwords">#search.details#</a>]</p>
    </if>
    
    <if @debug_p@>
      <p>#search.Searched_for_query#</p>
      <p>#search.Results_count#</p>
    </if>

