<master>
<property name="context">@context;noquote@</property>
<property name="doc(title)">@party_name;noquote@</property>

<h3>Attributes</h3>

<ul>
 <if @attributes:rowcount@ eq "0">
  <li> <em>There are no attributes for parties of this type</em> </li>
 </if>
 <else>
  <multiple name="attributes">
   <li> @attributes.pretty_name@: 
   <if @attributes.value@ nil>
     <em>(no value)</em>
   </if><else>
      @attributes.value@
   </else>
   <if @write_p@ eq 1>
     (<a href="../attributes/edit-one?@attributes.export_vars@">edit</a>) 
   </if>
   </li>
  </multiple>
 </else>
</ul>


<if @admin_p@ eq 1>
  <h3>Extreme Actions</h3>
  <ul>
    <li> <a href=delete?party_id=@party_id@>Nuke this party</a>
  </ul>
</if>
