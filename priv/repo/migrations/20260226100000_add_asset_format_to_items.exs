defmodule VrexServer.Repo.Migrations.AddAssetFormatToItems do
  use Ecto.Migration

  def change do
    alter table(:items) do
      # "glb" | "obj" | "fbx" | "vrm" | "assetbundle"
      add :asset_format, :string, default: "glb"
      add :collider_enabled, :boolean, default: true
    end
  end
end
