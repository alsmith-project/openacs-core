-- Data model to support content repository of the ArsDigita
-- Community System

-- Copyright (C) 1999-2000 ArsDigita Corporation
-- Author: Karl Goldstein (karlg@arsdigita.com)

-- $Id$

-- This is free software distributed under the terms of the GNU Public
-- License.  Full text of the license is available from the GNU Project:
-- http://www.fsf.org/copyleft/gpl.html

create view content_item_globals as 
select -100 as c_root_folder_id;

-- create or replace package body content_item
-- function get_root_folder
create function content_item__get_root_folder (integer)
returns integer as '
declare
  get_root_folder__item_id                alias for $1;  
  v_folder_id                             cr_folders.folder_id%TYPE;
begin

  if get_root_folder__item_id is NULL then

    v_folder_id := content_item_globals.c_root_folder_id;

  else

--    select
--      item_id into v_folder_id
--    from
--      cr_items
--    where 
--      parent_id = 0
--    connect by
--      prior parent_id = item_id
--    start with
--      item_id = get_root_folder__item_id;    

    select
      i2.item_id into v_folder_id
    from
      cr_items i1, cr_items i2
    where 
      i2.parent_id = 0
    and 
      i1.item_id = get_root_folder__item_id
    and
      i2.tree_sortkey <= i1.tree_sortkey
    and
      i1.tree_sortkey like (i2.tree_sortkey || ''%'');

    if NOT FOUND then
       raise EXCEPTION '' -20000: Could not find a root folder for item ID %. Either the item does not exist or its parent value is corrupted.'', get_root_folder__item_id;
    end if;
  end if;    

  return v_folder_id;
 
end;' language 'plpgsql';


-- function new
create function content_item__new (varchar,integer,integer,varchar,timestamp,integer,integer,varchar,varchar,varchar,varchar,varchar,varchar,varchar,varchar,integer)
returns integer as '
declare
  new__name                   alias for $1;  
  new__parent_id              alias for $2;  
  new__item_id                alias for $3;  
  new__locale                 alias for $4;  
  new__creation_date          alias for $5;  
  new__creation_user          alias for $6;  
  new__context_id             alias for $7;  
  new__creation_ip            alias for $8;  
  new__item_subtype           alias for $9;  
  new__content_type           alias for $10; 
  new__title                  alias for $11; 
  new__description            alias for $12; 
  new__mime_type              alias for $13; 
  new__nls_language           alias for $14; 
  new__text                   alias for $15; 
-- changed to integer for blob_id
  new__data                   alias for $16; 
--  relation_tag                alias for $17; 
--  is_live                     alias for $18; 
  new__relation_tag           varchar default null;
  new__is_live                boolean default ''f'';

  v_parent_id                 cr_items.parent_id%TYPE;
  v_parent_type               acs_objects.object_type%TYPE;
  v_item_id                   cr_items.item_id%TYPE;
  v_revision_id               cr_revisions.revision_id%TYPE;
  v_title                     cr_revisions.title%TYPE;
  v_rel_id                    acs_objects.object_id%TYPE;
  v_rel_tag                   cr_child_rels.relation_tag%TYPE;
  v_context_id                acs_objects.context_id%TYPE;
begin

  -- if content_item.is_subclass(item_subtype,''content_item'') = ''f'' then
  --  raise_application_error(-20000, ''The object_type '' || item_subtype || 
  --    '' does not inherit from content_item.'');
  -- end if;

  -- place the item in the context of the pages folder if no
  -- context specified 

  if new__parent_id is null then
    v_parent_id := content_item_globals.c_root_folder_id;
  else
    v_parent_id := new__parent_id;
  end if;

  -- Determine context_id
  if new__context_id is null then
    v_context_id := v_parent_id;
  else
    v_context_id := new__context_id;
  end if;

  if v_parent_id = 0 or 
    content_folder__is_folder(v_parent_id) = ''t'' then

    if v_parent_id != 0 and 
      content_folder__is_registered(
        v_parent_id, new__content_type, ''f'') = ''f'' then

      raise EXCEPTION ''-20000: This item\\\'s content type % is not registered to this folder %'', new__content_type, v_parent_id;
    end if;

  else if v_parent_id != 0 then

     select object_type into v_parent_type from acs_objects
       where object_id = v_parent_id;

     if NOT FOUND then 
       raise EXCEPTION ''-20000: Invalid parent ID % specified in content_item.new'',  v_parent_id;
     end if;

     if content_item__is_subclass(v_parent_type, ''content_item'') = ''t'' and
	content_item__is_valid_child(v_parent_id, new__content_type) = ''f'' then

       raise EXCEPTION ''-20000: This item\\\'s content type % is not allowed in this container %'', new__content_type, v_parent_id;
     end if;

  end if; end if;

  -- Create the object

  v_item_id := acs_object__new(
      new__item_id,
      new__item_subtype, 
      new__creation_date, 
      new__creation_user, 
      new__creation_ip, 
      v_context_id
  );

  -- Turn off security inheritance if there is no security context
  --if context_id is null then
  --  update acs_objects set security_inherit_p = ''f''
  --    where object_id = v_item_id;
  --end if;

  insert into cr_items (
    item_id, name, content_type, parent_id
  ) values (
    v_item_id, new__name, new__content_type, v_parent_id
  );

  -- if the parent is not a folder, insert into cr_child_rels
  if v_parent_id != 0 and
    content_folder__is_folder(v_parent_id) = ''f'' and 
    content_item__is_valid_child(v_parent_id, new__content_type) = ''t'' then

    v_rel_id := acs_object__new(
      null,
      ''cr_item_child_rel'',
      now(),
      null,
      null,
      v_parent_id
    );

    if new__relation_tag is null then
      v_rel_tag := content_item__get_content_type(v_parent_id) 
        || ''-'' || new__content_type;
    else
      v_rel_tag := new__relation_tag;
    end if;

    insert into cr_child_rels (
      rel_id, parent_id, child_id, relation_tag, order_n
    ) values (
      v_rel_id, v_parent_id, v_item_id, v_rel_tag, v_item_id
    );

  end if;

  -- use the name of the item if no title is supplied
  if new__title is null then
    v_title := new__name;
  else
    v_title := new__title;
  end if;

  -- create the revision if data or title or text is not null
  -- note that the caller could theoretically specify both text
  -- and data, in which case the text is ignored.

  if new__data is not null then

    v_revision_id := content_revision__new(
	v_title,
	new__description,
        now(),
	new__mime_type,
	new__nls_language,
	new__data,
        v_item_id,
        null,
        new__creation_date, 
        new__creation_user, 
        new__creation_ip
    );

  else if new__title is not null or 
      new__text is not null then

    v_revision_id := content_revision__new(
	v_title,
	new__description,
        now(),
	new__mime_type,
        null,
	new__text,
	v_item_id,
        null,
        new__creation_date, 
        new__creation_user, 
        new__creation_ip
    );

  end if; end if;

  -- make the revision live if is_live is ''t''
  if new__is_live = ''t'' then
    PERFORM content_item__set_live_revision(v_revision_id);
  end if;

  -- Have the new item inherit the permission of the parent item
  -- if no security context was specified
  --if parent_id is not null and context_id is null then
  --  content_permission.inherit_permissions (
  --    parent_id, v_item_id, creation_user
  --  );
  --end if;

  return v_item_id;
 
end;' language 'plpgsql';

create function content_item__new(varchar,integer,varchar,text,text) 
returns integer as '
declare
        new__name               alias for $1;
        new__parent_id          alias for $2;
        new__title              alias for $3;
        new__description        alias for $4;
        new__text               alias for $5;
begin
        return content_item__new(new__name,
                                 new__parent_id,
                                 null,
                                 null,
                                 now(),
                                 null,
                                 null,
                                 null,
                                 ''content_item'',
                                 ''content_revision'',   
                                 new__title,
                                 new__description,
                                 ''text/plain'',
                                 null,
                                 new__text,
                                 null
               );
                                 
end;' language 'plpgsql';

create function content_item__new(varchar,integer) returns integer as '
declare
        new__name       alias for $1;
        new__parent_id  alias for $2;
begin
        return content_item__new(new__name,
                                 new__parent_id,
                                 null,
                                 null,
                                 null);
end;' language 'plpgsql';

-- function is_published
create function content_item__is_published (integer)
returns boolean as '
declare
  is_published__item_id                alias for $1;  
begin

  select
    1
  from
    cr_items
  where
    live_revision is not null
  and
    publish_status = ''live''
  and
    item_id = is_published__item_id;

  if NOT FOUND then 
     return ''f'';
  else 
     return ''t'';
  end if;
 
end;' language 'plpgsql';


-- function is_publishable
create function content_item__is_publishable (integer)
returns boolean as '
declare
  is_publishable__item_id                alias for $1;  
  v_child_count                          integer;       
  v_rel_count                            integer;       
  v_template_id                          cr_templates.template_id%TYPE;
  v_child_type                           record;
  v_rel_type                             record;
  v_pub_wf                               record;
begin

  -- validate children
  -- make sure the # of children of each type fall between min_n and max_n
  for v_child_type in select
                        child_type, min_n, max_n
                      from
                        cr_type_children
                      where
                        parent_type = content_item__get_content_type(is_publishable__item_id) 
  LOOP
    select
      count(rel_id) into v_child_count
    from
      cr_child_rels
    where
      parent_id = is_publishable__item_id
    and
      content_item__get_content_type(child_id) = v_child_type.child_type;

    -- make sure # of children is in range
    if v_child_type.min_n is not null 
      and v_child_count < v_child_type.min_n then
      return ''f'';
    end if;
    if v_child_type.max_n is not null
      and v_child_count > v_child_type.max_n then
      return ''f'';
    end if;

  end LOOP;

  if NOT FOUND then 
     return ''f'';
  end if;

  -- validate relations
  -- make sure the # of ext links of each type fall between min_n and max_n
  for v_rel_type in select
                      target_type, min_n, max_n
                    from
                      cr_type_relations
                    where
                      content_type = content_item__get_content_type(is_publishable__item_id)

  LOOP
    select
      count(rel_id) into v_rel_count
    from
      cr_item_rels i, acs_objects o
    where
      i.related_object_id = o.object_id
    and
      i.item_id = is_publishable__item_id
    and
      coalesce(content_item__get_content_type(o.object_id),o.object_type) = v_rel_type.target_type;
      
    -- make sure # of object relations is in range
    if v_rel_type.min_n is not null 
      and v_rel_count < v_rel_type.min_n then
      return ''f'';
    end if;
    if v_rel_type.max_n is not null 
      and v_rel_count > v_rel_type.max_n then
      return ''f'';
    end if;
  end loop;

  if NOT FOUND then 
     return ''f'';
  end if;

  -- validate publishing workflows
  -- make sure any ''publishing_wf'' associated with this item are finished
  -- KG: logic is wrong here.  Only the latest workflow matters, and even
  -- that is a little problematic because more than one workflow may be
  -- open on an item.  In addition, this should be moved to CMS.

  for v_pub_wf in  select
                     case_id, state
                   from
                     wf_cases
                   where
                     workflow_key = ''publishing_wf''
                   and
                     object_id = is_publishable__item_id;

  LOOP
    if v_pub_wf.state != ''finished'' then
       return ''f'';
    end if;
  end loop;

  if NOT FOUND then 
     return ''f'';
  end if;

  return ''t'';
 
end;' language 'plpgsql';


-- function is_valid_child
create function content_item__is_valid_child (integer,varchar)
returns boolean as '
declare
  is_valid_child__item_id                alias for $1;  
  is_valid_child__content_type           alias for $2;  
  v_is_valid_child                       boolean;       
  v_max_children                         cr_type_children.max_n%TYPE;
  v_n_children                           integer;       
begin

  v_is_valid_child := ''f'';

  -- first check if content_type is a registered child_type
  select
    max_n into v_max_children
  from
    cr_type_children
  where
    parent_type = content_item__get_content_type(is_valid_child__item_id)
  and
    child_type = is_valid_child__content_type;

  if NOT FOUND then 
     return ''f'';
  end if;

  -- if the max is null then infinite number is allowed
  if v_max_children is null then
    return ''t'';
  end if;

  -- next check if there are already max_n children of that content type
  select
    count(rel_id) into v_n_children
  from
    cr_child_rels
  where
    parent_id = is_valid_child__item_id
  and
    content_item__get_content_type(child_id) = is_valid_child__content_type;

  if NOT FOUND then 
     return ''f'';
  end if;

  if v_n_children < v_max_children then
    v_is_valid_child := ''t'';
  end if;

  return v_is_valid_child;
 
end;' language 'plpgsql';


/* delete a content item
 1) delete all associated workflows
 2) delete all symlinks associated with this object
 3) delete any revisions for this item
 4) unregister template relations
 5) delete all permissions associated with this item
 6) delete keyword associations
 7) delete all associated comments */
-- procedure delete
create function content_item__delete (integer)
returns integer as '
declare
  delete__item_id                alias for $1;  
  v_wf_cases_val                 record;
  v_symlink_val                  record;
  v_revision_val                 record;
  v_rel_val                      record;
begin

  raise NOTICE ''Deleting associated workflows...'';
  -- 1) delete all workflow cases associated with this item
  for v_wf_cases_val in select
                          case_id
                        from
                          wf_cases
                        where
                          object_id = delete__item_id 
  LOOP
    PERFORM workflow_case__delete(v_wf_cases_val.case_id);
  end loop;

  raise NOTICE ''Deleting symlinks...'';
  -- 2) delete all symlinks to this item
  for v_symlink_val in select 
                         symlink_id
                       from 
                         cr_symlinks
                       where 
                         target_id = delete__item_id 
  LOOP
    PERFORM content_symlink__delete(v_symlink_val.symlink_id);
  end loop;

  raise NOTICE ''Unscheduling item...'';
  delete from cr_release_periods
    where item_id = delete__item_id;

  raise NOTICE ''Deleting associated revisions...'';
  -- 3) delete all revisions of this item
  delete from cr_item_publish_audit
    where item_id = delete__item_id;

  for v_revision_val in select
                          revision_id 
                        from
                          cr_revisions
                        where
                          item_id = delete__item_id 
  LOOP
    PERFORM content_revision__delete(v_revision_val.revision_id);
  end loop;
  
  raise NOTICE ''Deleting associated item templates...'';
  -- 4) unregister all templates to this item
  delete from cr_item_template_map
    where item_id = delete__item_id; 

  raise NOTICE ''Deleting item relationships...'';
  -- Delete all relations on this item
  for v_rel_val in select
                     rel_id
                   from
                     cr_item_rels
                   where
                     item_id = delete__item_id
                   or
                     related_object_id = delete__item_id 
  LOOP
    PERFORM acs_rel__delete(v_rel_val.rel_id);
  end loop;  

  raise NOTICE ''Deleting child relationships...'';
  for v_rel_val in select
                     rel_id
                   from
                     cr_child_rels
                   where
                     child_id = delete__item_id 
  LOOP
    PERFORM acs_rel__delete(v_rel_val.rel_id);
  end loop;  

  raise NOTICE ''Deleting parent relationships...'';
  for v_rel_val in select
                     rel_id, child_id
                   from
                     cr_child_rels
                   where
                     parent_id = delete__item_id 
  LOOP
    PERFORM acs_rel__delete(v_rel_val.rel_id);
    PERFORM content_item__delete(v_rel_val.child_id);
  end loop;  

  raise NOTICE ''Deleting associated permissions...'';
  -- 5) delete associated permissions
  delete from acs_permissions
    where object_id = delete__item_id;

  raise NOTICE ''Deleting keyword associations...'';
  -- 6) delete keyword associations
  delete from cr_item_keyword_map
    where item_id = delete__item_id;

  raise NOTICE ''Deleting associated comments...'';
  -- 7) delete associated comments
  PERFORM journal_entry__delete_for_object(delete__item_id);

  -- context_id debugging loop
  --for v_error_val in c_error_cur loop
  --  raise NOTICE ''ID='' || v_error_val.object_id || '' TYPE='' 
  --    || v_error_val.object_type);
  --end loop;

  raise NOTICE ''Deleting content item...'';
  PERFORM acs_object__delete(delete__item_id);

  return 0; 
end;' language 'plpgsql';


-- procedure rename
create function content_item__rename (integer,varchar)
returns integer as '
declare
  rename__item_id                alias for $1;  
  rename__name                   alias for $2;  
  exists_id                      integer;       
begin
  select
    item_id
  into 
    exists_id
  from 
    cr_items
  where
    name = rename__name
  and 
    parent_id = (select 
	           parent_id
		 from
		   cr_items
		 where
		   item_id = rename__item_id);
  if NOT FOUND then
    update cr_items
      set name = rename__name
      where item_id = rename__item_id;
  else
    if exists_id != rename__item_id then
      raise EXCEPTION ''-20000: An item with the name % already exists in this directory.'', rename__name;
    end if;
  end if;

  return 0; 
end;' language 'plpgsql';


-- function get_id
create function content_item__get_id (varchar,integer,boolean)
returns integer as '
declare
  get_id__item_path              alias for $1;  
  get_id__root_folder_id         alias for $2;  
  get_id__resolve_index          alias for $3;  
  v_item_path                    varchar; 
  v_root_folder_id               cr_items.item_id%TYPE;
  get_id__parent_id              integer;       
  child_id                       integer;       
  start_pos                      integer default 1;        
  end_pos                        integer;       
  counter                        integer default 0;       
  item_name                      varchar;  
begin

  v_root_folder_id := coalesce(get_id__root_folder_id, 
                               content_item_globals.c_root_folder_id);

  -- If the request path is the root, then just return the root folder
  if get_id__item_path = ''/'' then
    return v_root_folder_id;
  end if;  

  -- Remove leading, trailing spaces, leading slashes
  v_item_path := rtrim(ltrim(trim(get_id__item_path), ''/''), ''/'');

  get_id__parent_id := v_root_folder_id;

  -- if parent_id is a symlink, resolve it
  get_id__parent_id := content_symlink__resolve(get_id__parent_id);

  LOOP
    -- FIXME: this use of instr in oracle code seems incorrect.
    -- end_pos := instr(v_item_path, ''/'', start_pos);
    end_pos := instr(v_item_path, ''/'', 1);

    if end_pos = 0 then
      item_name := substr(v_item_path, 1);
    else
      item_name := substr(v_item_path, 1, end_pos - start_pos);
    end if;

    select 
      item_id into child_id
    from 
      cr_items
    where
      parent_id = get_id__parent_id
    and
      name = item_name;

    if NOT FOUND then 
       return null;
    end if;

    exit when end_pos = 0;

    get_id__parent_id := child_id;

    -- if parent_id is a symlink, resolve it
    get_id__parent_id := content_symlink__resolve(get_id__parent_id);

    start_pos := end_pos + 1;
    v_item_path := substr(v_item_path, start_pos);
      
  end loop;

  if get_id__resolve_index = ''t'' then

    -- if the item is a folder and has an index page, then return

    if content_folder__is_folder(child_id ) = ''t'' and
      content_folder__get_index_page(child_id) is not null then 

      child_id := content_folder__get_index_page(child_id);
    end if;

  end if;

  return child_id;

-- exception
--   when NO_DATA_FOUND then 
--     return null;
 
end;' language 'plpgsql';


-- function get_path
create function content_item__get_path (integer,integer)
returns varchar as '
declare
  get_path__item_id                alias for $1;  
  get_path__root_folder_id         alias for $2;  
  v_count                          integer;       
  v_name                           varchar;  
  v_parent_id                      integer default 0;        
  v_tree_level                     integer;       
  v_resolved_root_id               integer;       
  v_rel_parent_id                  integer default 0;        
  v_rel_tree_level                 integer default 0;        
  v_path                           varchar default '''';  
begin

  -- check that the item exists
  select count(*) into v_count from cr_items where item_id = get_path__item_id;

  if v_count = 0 then
    raise EXCEPTION ''-20000: Invalid item ID: %'', item_id;
  end if;

  -- begin walking down the path to the item (from the repository root)
  open c_abs_cur;

  -- if the root folder is not null then prepare for a relative path

  if get_path__root_folder_id is not null then

    -- if root_folder_id is a symlink, resolve it (child items will point
    -- to the actual folder, not the symlink)

    v_resolved_root_id := content_symlink__resolve(get_path__root_folder_id);

    -- begin walking down the path to the root folder.  Discard
    -- elements of the item path as long as they are the same as the root
    -- folder

    open c_rel_cur;

    while v_parent_id = v_rel_parent_id loop
	fetch c_abs_cur into v_name, v_parent_id, v_tree_level;
	fetch c_rel_cur into v_rel_parent_id, v_rel_tree_level;
	exit when c_abs_cur%NOTFOUND or c_rel_cur%NOTFOUND;
    end loop;

    -- walk the remainder of the relative path, add a ''..'' for each 
    -- additional step

    loop
      exit when c_rel_cur%NOTFOUND;
      v_path := v_path || ''../'';
      fetch c_rel_cur into v_rel_parent_id, v_rel_tree_level;
    end loop;

    -- an item relative to itself is ''../item''
    if v_resolved_root_id = item_id then
	v_path := ''../'';
    end if;

  else
  
    -- this is an absolute path so prepend a ''/''
   v_path := ''/'';

   -- prime the pump to be consistent with relative path execution plan
   fetch c_abs_cur into v_name, v_parent_id, v_tree_level;	

  end if;

  -- loop over the remainder of the absolute path

  loop

    v_path := v_path || v_name;

    fetch c_abs_cur into v_name, v_parent_id, v_tree_level;

    exit when c_abs_cur%NOTFOUND;

    v_path := v_path || ''/'';

  end loop;

  return v_path;

 
end;' language 'plpgsql';


-- function get_virtual_path
create function content_item__get_virtual_path (integer,integer)
returns varchar as '
declare
  get_virtual_path__item_id               alias for $1;  
  get_virtual_path__root_folder_id        alias for $2;  
  v_path                                  varchar; 
  v_item_id                               cr_items.item_id%TYPE;
  v_is_folder                             boolean;       
  v_index                                 cr_items.item_id%TYPE;
begin

  -- first resolve the item
  v_item_id := content_symlink__resolve(get_virtual_path__item_id);

  v_is_folder := content_folder__is_folder(v_item_id);
  v_index := content_folder__get_index_page(v_item_id);

  -- if the folder has an index page
  if v_is_folder = ''t'' and v_index is not null then
    v_path := content_item__get_path(content_symlink__resolve(v_index));
  else
    v_path := content_item__get_path(v_item_id);
  end if;

  return v_path;
--  exception
--    when NO_DATA_FOUND then
--      return null;
 
end;' language 'plpgsql';


-- procedure write_to_file
create function content_item__write_to_file (integer,varchar)
returns integer as '
declare
  item_id                alias for $1;  
  root_path              alias for $2;  
  -- blob_loc               cr_revisions.content%TYPE;
  -- v_revision             cr_items.live_revision%TYPE;
begin
  
  -- FIXME:
  raise NOTICE ''not implemented for postgresql'';
/*
  v_revision := content_item__get_live_revision(item_id);

  select content into blob_loc from cr_revisions 
    where revision_id = v_revision;

  if NOT FOUND then 
    raise EXCEPTION ''-20000: No live revision for content item % in content_item.write_to_file.'', item_id;    
  end if;
  
  PERFORM blob_to_file(root_path || content_item__get_path(item_id), blob_loc);
*/
  return 0; 
end;' language 'plpgsql';


-- procedure register_template
create function content_item__register_template (integer,integer,varchar)
returns integer as '
declare
  register_template__item_id                alias for $1;  
  register_template__template_id            alias for $2;  
  register_template__use_context            alias for $3;  
                                        
begin

 -- register template if it is not already registered
  insert into cr_item_template_map
  select
    register_template__template_id as template_id,
    register_template__item_id as item_id,
    register_template__use_context as use_context
  from
    dual
  where
    not exists ( select 1
                 from
                   cr_item_template_map
                 where
                   item_id = register_template__item_id
                 and
                   template_id = register_template__template_id
                 and
                   use_context = register_template__use_context );

  return 0; 
end;' language 'plpgsql';


-- procedure unregister_template
create function content_item__unregister_template (integer,integer,varchar)
returns integer as '
declare
  unregister_template__item_id                alias for $1;  
  unregister_template__template_id            alias for $2;  
  unregister_template__use_context            alias for $3;  
                                        
begin

  if unregister_template__use_context is null and 
     unregister_template__template_id is null then

    delete from cr_item_template_map
      where item_id = unregister_template__item_id;

  else if unregister_template__use_context is null then

    delete from cr_item_template_map
      where template_id = unregister_template__template_id
      and item_id = unregister_template__item_id;

  else if unregister_template__template_id is null then

    delete from cr_item_template_map
      where item_id = unregister_template__item_id
      and use_context = unregister_template__use_context;

  else

    delete from cr_item_template_map
      where template_id = unregister_template__template_id
      and item_id = unregister_template__item_id
      and use_context = unregister_template__use_context;

  end if; end if; end if;

  return 0; 
end;' language 'plpgsql';


-- function get_template
create function content_item__get_template (integer,varchar)
returns integer as '
declare
  get_template__item_id                alias for $1;  
  get_template__use_context            alias for $2;  
  v_template_id                        cr_templates.template_id%TYPE;
  v_content_type                       cr_items.content_type%TYPE;
begin

  -- look for a template assigned specifically to this item
  select
    template_id 
  into 
     v_template_id
  from
    cr_item_template_map
  where
    item_id = get_template__item_id
  and
    use_context = get_template__use_context;
  -- otherwise get the default for the content type
  if NOT FOUND then
    select 
      m.template_id
    into 
      v_template_id
    from
      cr_items i, cr_type_template_map m
    where
      i.item_id = get_template__item_id
    and
      i.content_type = m.content_type
    and
      m.use_context = get_template__use_context
    and
      m.is_default = ''t'';

    if NOT FOUND then
       return null;
    end if;
  end if;

  return v_template_id;
 
end;' language 'plpgsql';


-- function get_content_type
create function content_item__get_content_type (integer)
returns varchar as '
declare
  get_content_type__item_id                alias for $1;  
  v_content_type                           cr_items.content_type%TYPE;
begin

  select
    content_type into v_content_type
  from 
    cr_items
  where 
    item_id = get_content_type__item_id;  

  if NOT FOUND then 
     return null;
  end if;

  return v_content_type;
 
end;' language 'plpgsql';


-- function get_live_revision
create function content_item__get_live_revision (integer)
returns integer as '
declare
  get_live_revision__item_id                alias for $1;  
  v_revision_id                             acs_objects.object_id%TYPE;
begin

  select
    live_revision into v_revision_id
  from
    cr_items
  where
    item_id = get_live_revision__item_id;

  if NOT FOUND then 
     return null;
  else 
     return v_revision_id;
  end if;
 
end;' language 'plpgsql';


-- procedure set_live_revision
create function content_item__set_live_revision (integer,varchar)
returns integer as '
declare
  set_live_revision__revision_id            alias for $1;  
  set_live_revision__publish_status         alias for $2;  
begin

  update
    cr_items
  set
    live_revision = set_live_revision__revision_id,
    publish_status = set_live_revision__publish_status
  where
    item_id = (select
                 item_id
               from
                 cr_revisions
               where
                 revision_id = set_live_revision__revision_id);

  update
    cr_revisions
  set
    publish_date = now()
  where
    revision_id = set_live_revision__revision_id;

  return 0; 
end;' language 'plpgsql';


-- procedure unset_live_revision
create function content_item__unset_live_revision (integer)
returns integer as '
declare
  unset_live_revision__item_id                alias for $1;  
begin

  update
    cr_items
  set
    live_revision = NULL
  where
    item_id = unset_live_revision__item_id;

  -- if an items publish status is "live", change it to "ready"
  update
    cr_items
  set
    publish_status = ''production''
  where
    publish_status = ''live''
  and
    item_id = unset_live_revision__item_id;

  return 0; 
end;' language 'plpgsql';


-- procedure set_release_period
create function content_item__set_release_period (integer,timestamp,timestamp)
returns integer as '
declare
  set_release_period__item_id                alias for $1;  
  set_release_period__start_when             alias for $2;
  set_release_period__end_when               alias for $3;
  v_count                                    integer;       
begin

  select count(*) into v_count from cr_release_periods 
    where item_id = set_release_period__item_id;

  if v_count = 0 then
    insert into cr_release_periods (
      item_id, start_when, end_when
    ) values (
      set_release_period__item_id, 
      set_release_period__start_when, 
      set_release_period__end_when
    );
  else
    update cr_release_periods
      set start_when = set_release_period__start_when,
      end_when = set_release_period__end_when
    where
      item_id = set_release_period__item_id;
  end if;

  return 0; 
end;' language 'plpgsql';


-- function get_revision_count
create function content_item__get_revision_count (integer)
returns number as '
declare
  get_revision_count__item_id   alias for $1;  
  v_count                       integer;       
begin

  select
    count(*) into v_count
  from 
    cr_revisions
  where
    item_id = get_revision_count__item_id;

  return v_count;
 
end;' language 'plpgsql';


-- function get_context
create function content_item__get_context (integer)
returns integer as '
declare
  get_context__item_id                alias for $1;  
  v_context_id                        acs_objects.context_id%TYPE;
begin

  select
    context_id
  into
    v_context_id
  from
    acs_objects
  where
    object_id = get_context__item_id;

  if NOT FOUND then 
     raise EXCEPTION ''-20000: Content item % does not exist in content_item.get_context'', item_id;
  end if;

  return v_context_id;
 
end;' language 'plpgsql';


-- 1) make sure we are not moving the item to an invalid location:
--   that is, the destination folder exists and is a valid folder
-- 2) make sure the content type of the content item is registered
--   to the target folder
-- 3) update the parent_id for the item

-- procedure move
create function content_item__move (integer,integer)
returns integer as '
declare
  move__item_id                alias for $1;  
  move__target_folder_id       alias for $2;  
begin

  if content_folder__is_folder(move__item_id) = ''t'' then
    content_folder__move(move__item_id, move__target_folder_id);
  else if content_folder__is_folder(move__target_folder_id) = ''t'' then
   

    if content_folder__is_registered(move__target_folder_id,
          content_item__get_content_type(move__item_id),''f'') = ''t'' and
       content_folder__is_registered(move__target_folder_id,
          content_item__get_content_type(content_symlink__resolve(move__item_id)),''f'') = ''t''
      then

    -- update the parent_id for the item
    update cr_items 
      set parent_id = move__target_folder_id
      where item_id = move__item_id;
    end if;

  end if; end if;

  return 0; 
end;' language 'plpgsql';


-- procedure copy
create function content_item__copy (integer,integer,integer,varchar)
returns integer as '
declare
  item_id                alias for $1;  
  target_folder_id       alias for $2;  
  creation_user          alias for $3;  
  creation_ip            alias for $4;  
  copy_id                cr_items.item_id%TYPE;
begin

  copy_id := copy2(item_id, target_folder_id, creation_user, creation_ip);

  return 0; 
end;' language 'plpgsql';

-- copy a content item to a target folder
-- 1) make sure we are not copying the item to an invalid location:
--   that is, the destination folder exists, is a valid folder,
--   and is not the current folder
-- 2) make sure the content type of the content item is registered
--   with the current folder
-- 3) create a new item with no revisions in the target folder
-- 4) copy the latest revision from the original item to the new item (if any)

-- function copy2
create function content_item__copy2 (integer,integer,integer,varchar)
returns integer as '
declare
  copy2__item_id                alias for $1;  
  copy2__target_folder_id       alias for $2;  
  copy2__creation_user          alias for $3;  
  copy2__creation_ip            alias for $4;  
  v_current_folder_id           cr_folders.folder_id%TYPE;
  v_num_revisions               integer;       
  v_name                        cr_items.name%TYPE;
  v_content_type                cr_items.content_type%TYPE;
  v_locale                      cr_items.locale%TYPE;
  v_item_id                     cr_items.item_id%TYPE;
  v_revision_id                 cr_revisions.revision_id%TYPE;
  v_is_registered               boolean;       
  v_old_revision_id             cr_revisions.revision_id%TYPE;
  v_new_revision_id             cr_revisions.revision_id%TYPE;
begin

  -- call content_folder.copy if the item is a folder
  if content_folder__is_folder(copy2__item_id) = ''t'' then
    PERFORM content_folder__copy(
        copy2__item_id,
        copy2__target_folder_id,
        copy2__creation_user,
        copy2__creation_ip
    );
  -- call content_symlink.copy if the item is a symlink
  else if content_symlink__is_symlink(copy2__item_id) = ''t'' then
    PERFORM content_symlink__copy(
        copy2__item_id,
        copy2__target_folder_id,
        copy2__creation_user,
        copy2__creation_ip
    );
  -- make sure the target folder is really a folder
  else if content_folder__is_folder(copy2__target_folder_id) = ''t'' then

    select
      parent_id
    into
      v_current_folder_id
    from
      cr_items
    where
      item_id = copy2__item_id;

    -- can''t copy to the same folder
    if copy2__target_folder_id != v_current_folder_id then

      select
        content_type, name, locale,
        coalesce(live_revision, latest_revision)
      into
        v_content_type, v_name, v_locale, v_revision_id
      from
        cr_items
      where
        item_id = copy2__item_id;

      -- make sure the content type of the item is registered to the folder
      v_is_registered := content_folder__is_registered(
          copy2__target_folder_id,
          v_content_type,
          ''f''
      );

      if v_is_registered = ''t'' then
        -- create the new content item
        v_item_id := content_item__new(
            v_name,
            copy2__target_folder_id,
            null,
            v_locale,
            now(),
            copy2__creation_user,
            null,
            copy2__creation_ip,
            ''content_item'',            
            v_content_type,
            null,
            null,
            ''text/plain'',
            null,
            null,
            null            
        );

        -- get the latest revision of the old item
        select
          latest_revision into v_old_revision_id
        from
          cr_items
        where
          item_id = copy2__item_id;

        -- copy the latest revision (if any) to the new item
        if v_old_revision_id is not null then
          v_new_revision_id := content_revision__copy (
              v_old_revision_id,
              null,
              v_item_id,
              copy2__creation_user,
              copy2__creation_ip
          );
        end if;
      end if;


    end if;
  end if; end if; end if;

  return v_item_id;
 
end;' language 'plpgsql';


-- function get_latest_revision
create function content_item__get_latest_revision (integer)
returns integer as '
declare
  get_latest_revision__item_id                alias for $1;  
  v_revision_id                               integer;       
begin
  select 
    r.revision_id 
  into 
    v_revision_id
  from 
    cr_revisions r, acs_objects o
  where 
    r.revision_id = o.object_id
  and 
    r.item_id = get_latest_revision__item_id
  order by 
    o.creation_date desc;

  if NOT FOUND then
     return null;
  end if;

  return v_revision_id
 
end;' language 'plpgsql';


-- function get_best_revision
create function content_item__get_best_revision (integer)
returns integer as '
declare
  get_best_revision__item_id                alias for $1;  
  v_revision_id                             cr_revisions.revision_id%TYPE;
begin
    
  select
    coalesce(live_revision, latest_revision )
  into
    v_revision_id
  from
    cr_items
  where
    item_id = get_best_revision__item_id;

  if NOT FOUND then 
     return null;
  end if;

  return v_revision_id;
 
end;' language 'plpgsql';


-- function get_title
create function content_item__get_title (integer,boolean)
returns varchar as '
declare
  get_title__item_id                alias for $1;  
  get_title__is_live                alias for $2;  
  v_title                           cr_revisions.title%TYPE;
  v_content_type                    cr_items.content_type%TYPE;
begin
  
  select content_type into v_content_type from cr_items 
    where item_id = get_title__item_id;

  if v_content_type = ''content_folder'' then
    select label into v_title from cr_folders 
      where folder_id = get_title__item_id;
  else if v_content_type = ''content_symlink'' then
    select label into v_title from cr_symlinks 
      where symlink_id = get_title__item_id;
  else
    if get_title__is_live then
      select
	title into v_title
      from
	cr_revisions r, cr_items i
      where
        i.item_id = get_title__item_id
      and
        r.revision_id = i.live_revision;
    else
      select
	title into v_title
      from
	cr_revisions r, cr_items i
      where
        i.item_id = get_title__item_id
      and
        r.revision_id = i.latest_revision;
    end if;
  end if; end if;

  return v_title;

end;' language 'plpgsql';


-- function get_publish_date
create function content_item__get_publish_date (integer,boolean)
returns timestamp as '
declare
  get_publish_date__item_id                alias for $1;  
  get_publish_date__is_live                alias for $2;  
  v_revision_id                            cr_revisions.revision_id%TYPE;
  v_publish_date                           cr_revisions.publish_date%TYPE;
begin
  
  if get_publish_date__is_live then
    select
	publish_date into v_publish_date
    from
	cr_revisions r, cr_items i
    where
      i.item_id = get_publish_date__item_id
    and
      r.revision_id = i.live_revision;
  else
    select
	publish_date into v_publish_date
    from
	cr_revisions r, cr_items i
    where
      i.item_id = get_publish_date__item_id
    and
      r.revision_id = i.latest_revision;
  end if;

  if NOT FOUND then 
     return null;
  end if;

  return v_publish_date;
 
end;' language 'plpgsql';


-- function is_subclass
create function content_item__is_subclass (varchar,varchar)
returns boolean as '
declare
  is_subclass__object_type            alias for $1;  
  is_subclass__supertype              alias for $2;  
  v_subclass_p                        boolean;      
  v_inherit_val                       record;
begin

  v_subclass_p := ''f'';

--                       select
--                         object_type
--                       from
--                         acs_object_types  
--                       connect by
--                         prior object_type = supertype
--                       start with 
--                         object_type = is_subclass__supertype

  for v_inherit_val in select
                         object_type
                       from
                         acs_object_types  
                       where
                         tree_sortkey 
                            like (select object_type || ''%'' 
                                    from acs_object_types 
                                   where object_type = is_subclass__supertype)
                       order by tree_sortkey
  LOOP
    if v_inherit_val.object_type = is_subclass__object_type then
         v_subclass_p := ''t'';
    end if;
  end loop;

  return v_subclass_p;

end;' language 'plpgsql';


-- function relate
create function content_item__relate (integer,integer,varchar,integer,varchar)
returns integer as '
declare
  relate__item_id                alias for $1;  
  relate__object_id              alias for $2;  
  relate__relation_tag           alias for $3;  
  relate__order_n                alias for $4;  
  relate__relation_type          alias for $5;  
  v_content_type                 cr_items.content_type%TYPE;
  v_object_type                  acs_objects.object_type%TYPE;
  v_is_valid                     integer;       
  v_rel_id                       integer;       
  v_exists                       integer;       
  v_order_n                      cr_item_rels.order_n%TYPE;
begin

  -- check the relationship is valid
  v_content_type := content_item__get_content_type (relate__item_id);
  v_object_type := content_item__get_content_type (relate__object_id);

  select
    count(1) into v_is_valid
  from
    cr_type_relations
  where
    content_item__is_subclass( v_object_type, target_type ) = ''t''
  and
    content_item__is_subclass( v_content_type, content_type ) = ''t'';

  if v_is_valid = 0 then
    raise EXCEPTION ''-20000: There is no registered relation type matching this item relation.'';
  end if;

  if relate__item_id != relate__object_id then
    -- check that these two items are not related already
    --dbms_output.put_line( ''checking if the items are already related...'');
    
    select
      rel_id, 1 as v_exists into v_rel_id, v_exists
    from
      cr_item_rels
    where
      item_id = relate__item_id
    and
      related_object_id = relate__object_id
    and
      relation_tag = relate__relation_tag;

    if NOT FOUND then
       v_exists := 0;
    end if;
    
    -- if order_n is null, use rel_id (the order the item was related)
    if relate__order_n is null then
      v_order_n := v_rel_id;
    else
      v_order_n := relate__order_n;
    end if;


    -- if relationship does not exist, create it
    if v_exists <> 1 then
      --dbms_output.put_line( ''creating new relationship...'');
      v_rel_id := acs_object__new(
        null,
        relate__relation_type,
        now(),
        null,
        null,
        relate__item_id
      );
      insert into cr_item_rels (
        rel_id, item_id, related_object_id, order_n, relation_tag
      ) values (
        v_rel_id, relate__item_id, relate__object_id, v_order_n, 
        relate__relation_tag
      );

    -- if relationship already exists, update it
    else
      --dbms_output.put_line( ''updating existing relationship...'');
      update cr_item_rels set
        relation_tag = relate__relation_tag,
        order_n = v_order_n
      where
        rel_id = v_rel_id;
    end if;

  end if;

  return v_rel_id;
 
end;' language 'plpgsql';


-- procedure unrelate
create function content_item__unrelate (integer)
returns integer as '
declare
  unrelate__rel_id      alias for $1;  
begin

  -- delete the relation object
  PERFORM acs_rel__delete(unrelate__rel_id);

  -- delete the row from the cr_item_rels table
  delete from cr_item_rels where rel_id = unrelate__rel_id;

  return 0; 
end;' language 'plpgsql';


-- function is_index_page
create function content_item__is_index_page (integer,integer)
returns boolean as '
declare
  is_index_page__item_id                alias for $1;  
  is_index_page__folder_id              alias for $2;  
begin
  if content_folder__get_index_page(is_index_page__folder_id) = is_index_page__item_id then
    return ''t'';
  else
    return ''f'';
  end if;
 
end;' language 'plpgsql';


-- function get_parent_folder
create function content_item__get_parent_folder (integer)
returns integer as '
declare
  get_parent_folder__item_id               alias for $1;  
  v_folder_id                              cr_folders.folder_id%TYPE;
  v_parent_folder_p                        boolean default ''f'';       
begin

  while NOT v_parent_folder_p LOOP

    select
      parent_id, content_folder__is_folder(parent_id) 
    into 
      v_folder_id, v_parent_folder_p
    from
      cr_items
    where
      item_id = get_parent_folder__item_id;

    if NOT FOUND then
       return null;
    end if;

  end loop; 

  return v_folder_id;
 
end;' language 'plpgsql';

-- show errors


-- Trigger to maintain context_id in acs_objects
create function cr_items_update_tr () returns opaque as '
begin

  if new.parent_id <> old.parent_id then
    update acs_objects set context_id = new.parent_id
    where object_id = new.item_id;
  end if;

  return new;
end;' language 'plpgsql';

create trigger cr_items_update_tr after update on cr_items
for each row execute procedure cr_items_update_tr ();

-- show errors

-- Trigger to maintain publication audit trail
create function cr_items_publish_update_tr () returns opaque as '
begin
  if new.live_revision <> old.live_revision or
     new.publish_status <> old.publish_status
  then 

    insert into cr_item_publish_audit (
      item_id, old_revision, new_revision, old_status, new_status, publish_date
    ) values (
      new.item_id, old.live_revision, new.live_revision, 
      old.publish_status, new.publish_status,
      now()
    );

  end if;

  return new;

end;' language 'plpgsql';

create trigger cr_items_publish_update_tr before update on cr_items
for each row execute procedure cr_items_publish_update_tr ();

-- show errors


