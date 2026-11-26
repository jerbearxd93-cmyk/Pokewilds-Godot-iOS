extends RefCounted
static var directory := ""
static var last_error := ""
static var android_storage: Variant = null

static func root_path() -> String:
    if not directory.is_empty(): return directory
    # Android can move the whole live folder to external storage. iOS has no
    # shared external folder, but its own Documents folder is the one the Files
    # app browses, so the live folder lives there instead of in user://.
    directory = "user://"
    if OS.get_name() == "Android":
        if Engine.has_singleton("JavaClassWrapper"):
            android_storage = Engine.get_singleton("JavaClassWrapper").wrap("com.godot.game.PokeWildsStorage")
            if android_storage != null:
                var external: String = android_storage.getExternalRoot()
                if not external.is_empty(): directory = external
        if directory == "user://":
            last_error = "Android external storage is unavailable. Saves remain in private storage."
            push_error(last_error)
    elif OS.get_name() == "iOS":
        var documents := _ios_documents_root()
        if documents.is_empty():
            last_error = "The app Documents folder is unavailable. Saves remain in private storage."
            push_error(last_error)
        else:
            directory = documents
    return directory

static func path(relative: String) -> String:
    return root_path().path_join(relative)

## The app's own Documents folder, the one the Files app browses when the export
## exposes user data (user_data/accessible_from_files_app). Anything unhelpful
## from the platform returns "" so the caller keeps the private user:// root
## instead of writing into a folder that does not exist.
static func _ios_documents_root() -> String:
    var documents := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
    if documents.is_empty() or not documents.is_absolute_path(): return ""
    if not DirAccess.dir_exists_absolute(documents):
        if DirAccess.make_dir_recursive_absolute(documents) != OK: return ""
    return documents

static func initialize() -> Error:
    var error := _initialize_external()
    if error != OK:
        last_error = "External save migration failed; original private saves remain active. Error %d" % error
        directory = "user://"
        for folder in ["saves", "world_cache"]:
            DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path(folder)))
    if android_storage != null:
        if not android_storage.setActiveRoot(ProjectSettings.globalize_path(root_path())):
            last_error = "Cannot expose the live game folder in Android Files."
            push_error(last_error)
    return error

static func _initialize_external() -> Error:
    for folder in ["saves", "world_cache"]:
        var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path(folder)))
        if error != OK: return error
    if root_path() == "user://" or FileAccess.file_exists(path(".private-saves-migrated")): return OK
    var sources: Array[String] = ["game.ini"]
    for folder in ["saves", "world_cache"]:
        for filename in DirAccess.get_files_at("user://" + folder): sources.append(folder + "/" + filename)
    for relative in sources:
        var source := "user://" + relative
        var target := path(relative)
        if not FileAccess.file_exists(source) or FileAccess.file_exists(target): continue
        var temporary := target + ".migrating"
        var error := DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(temporary))
        if error != OK: return error
        if FileAccess.get_sha256(source) != FileAccess.get_sha256(temporary): return ERR_FILE_CORRUPT
        error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(target))
        if error != OK: return error
    var marker := FileAccess.open(path(".private-saves-migrated"), FileAccess.WRITE)
    if marker == null: return FileAccess.get_open_error()
    marker.store_string("Private originals retained. External saves are now authoritative.\n")
    return OK
