defmodule GaraWeb.Guardian do
  use Guardian, otp_app: :gara

  @impl true
  def subject_for_token(uid, _claims), do: {:ok, to_string(uid)}

  @impl true
  def resource_from_claims(%{"sub" => str}) do
    case Integer.parse(str) do
      {uid, ""} -> {:ok, uid}
      _ -> {:error, :invalid}
    end
  end

  def build_token(uid, room_name) do
    case encode_and_sign(uid, %{"room_name" => room_name}) do
      {:ok, token, _claims} -> {:ok, token}
      _ -> raise("cannot encode token")
    end
  end

  def decode_token(token) do
    case resource_from_token(token) do
      {:ok, uid, %{"room_name" => room_name}} -> {uid, room_name}
      _ -> nil
    end
  end
end
