import gleeunit
import lumina_messages

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn announce_me_round_trip_test() {
  let assert Ok(instance) =
    lumina_messages.string_to_instance_name("social.peoni.es")
  let assert Ok(alias) = lumina_messages.string_to_user_alias("mar")
  let message =
    lumina_messages.AnnounceMe(
      instance:,
      alias:,
      displayname: "Mar 🌷",
      creation: 1_795_216_191,
    )
  let assert Ok(bits) = lumina_messages.to_bits(message)
  assert lumina_messages.from_bits(bits) == Ok(message)
}
