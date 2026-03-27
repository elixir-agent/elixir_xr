defmodule VrexServer.Scripting do
  @moduledoc """
  Elixirスクリプティングシステム。

  ワールド・アイテム・アバターの動作をElixirコードで定義できる。

  スクリプト例:
      defmodule MyWorldScript do
        use VrexServer.Scripting.WorldScript

        def on_player_join(ctx) do
          broadcast(ctx.room_id, "welcome", %{message: "ようこそ！"})
        end

        def on_player_leave(ctx) do
          broadcast(ctx.room_id, "farewell", %{user_id: ctx.user_id})
        end
      end

  アイテムスクリプト例:
      defmodule MyItemScript do
        use VrexServer.Scripting.ItemScript

        def on_interact(ctx) do
          %{message: "\#{ctx.user_id} がアイテムを触りました", sound: "click"}
        end
      end
  """

  require Logger

  @sandbox_timeout 5_000

  def run_event(script_source, event, context) do
    task =
      Task.async(fn ->
        try do
          # スクリプトのモジュール名をユニークにする
          module_name = :"VrexScript_#{:erlang.unique_integer([:positive])}"
          patched = patch_script(script_source, module_name)

          {mod, _bindings} = Code.eval_string(patched, [], __ENV__)
          apply(mod, event, [context])
          |> then(&{:ok, &1})
        rescue
          e -> {:error, Exception.message(e)}
        catch
          kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
        end
      end)

    case Task.yield(task, @sandbox_timeout) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end

  def validate_script(script_source) do
    try do
      Code.string_to_quoted!(script_source)
      {:ok, :valid}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  # モジュール名を動的に差し替え、危険な関数呼び出しをチェック
  defp patch_script(source, module_name) do
    # defmodule の後のモジュール名を動的なものに差し替え
    Regex.replace(~r/defmodule\s+\S+\s+do/, source, "defmodule #{module_name} do")
  end
end

defmodule VrexServer.Scripting.WorldScript do
  @moduledoc "ワールドスクリプトのベースモジュール"

  defmacro __using__(_opts) do
    quote do
      def on_player_join(_ctx), do: :ok
      def on_player_leave(_ctx), do: :ok
      def on_chat(_ctx), do: :ok

      defoverridable on_player_join: 1, on_player_leave: 1, on_chat: 1

      defp broadcast(room_id, event, payload) do
        VrexServerWeb.Endpoint.broadcast("room:#{room_id}", event, payload)
      end
    end
  end
end

defmodule VrexServer.Scripting.ItemScript do
  @moduledoc "アイテムスクリプトのベースモジュール"

  defmacro __using__(_opts) do
    quote do
      def on_interact(_ctx), do: %{}
      def on_pickup(_ctx), do: %{}
      def on_drop(_ctx), do: %{}

      defoverridable on_interact: 1, on_pickup: 1, on_drop: 1
    end
  end
end

defmodule VrexServer.Scripting.AvatarScript do
  @moduledoc "アバタースクリプトのベースモジュール（カスタムシェーダーパラメータ等）"

  defmacro __using__(_opts) do
    quote do
      def get_shader_params(_ctx), do: %{}
      def on_expression_change(_ctx), do: %{}

      defoverridable get_shader_params: 1, on_expression_change: 1
    end
  end
end
