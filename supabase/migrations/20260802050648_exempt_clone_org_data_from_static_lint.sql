-- clone_org_data() deliberately combines a runtime temporary table with
-- dynamic SQL so it can clone a dependency-ordered set of workspace tables.
-- plpgsql_check cannot model temporary tables created inside a function and
-- reports _idmap as missing even though the clean rebuild and pgTAP suite
-- execute the function successfully. Keep static linting enabled everywhere
-- else and rely on the database execution/isolation tests for this function.

alter function public.clone_org_data(uuid, uuid, uuid)
  set plpgsql.enable_check to false;
