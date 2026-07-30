import os

import unreal


ASSET_ROOT = (
    "/Game/Pal/Model/Character/Player/Outfit/"
    "SK_Player_Female_Outfit_Cloth001"
)
ASSETS = [
    ("v01", "T_Player_Female_Outfit_Cloth001_v01_M01_B"),
    ("v01", "T_Player_Female_Outfit_Cloth001_v01_M02_B"),
    ("v01", "T_Player_Female_Outfit_Cloth001_v01_M03_B"),
    ("v02", "T_Player_Female_Outfit_Cloth001_v02_M01_B"),
    ("v02", "T_Player_Female_Outfit_Cloth001_v02_M02_B"),
    ("v03", "T_Player_Female_Outfit_Cloth001_v03_M01_B"),
    ("v03", "T_Player_Female_Outfit_Cloth001_v03_M02_B"),
]

asset_tools = unreal.AssetToolsHelpers.get_asset_tools()
for version, asset_name in ASSETS:
    source_png = os.path.abspath(
        os.path.join(
            unreal.Paths.project_dir(),
            "..",
            "Build",
            "ImportSources",
            f"{asset_name}.png",
        )
    )
    if not os.path.isfile(source_png):
        raise RuntimeError(f"Exact-name import source is missing: {source_png}")

    task = unreal.AssetImportTask()
    task.set_editor_property("filename", source_png)
    task.set_editor_property("destination_path", f"{ASSET_ROOT}/{version}")
    task.set_editor_property("destination_name", asset_name)
    task.set_editor_property("automated", True)
    task.set_editor_property("replace_existing", True)
    task.set_editor_property("save", True)
    asset_tools.import_asset_tasks([task])

    asset_path = f"{ASSET_ROOT}/{version}/{asset_name}.{asset_name}"
    texture = unreal.EditorAssetLibrary.load_asset(asset_path)
    if texture is None or texture.get_class().get_name() != "Texture2D":
        raise RuntimeError(f"Unreal did not create a Texture2D at {asset_path}")

    texture.set_editor_property("srgb", True)
    unreal.EditorAssetLibrary.save_loaded_asset(texture, only_if_is_dirty=False)
    unreal.log(f"PalMac checker texture created: {asset_path}")
