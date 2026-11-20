//// **Lumina >**
//// # Message en/decoding and packaging
////
//// Holds tools and definition for Lumina's `Polite Protocol` messages and its binary format.

// Lumina/Peonies
// Copyright (C) 2018-2026 MLC 'Strawmelonjuice' Bloeiman and contributors.
//
// This software is licensed under the European Union Public Licence (EUPL) v1.2.
// You may not use this work except in compliance with the Licence.
// You may obtain a copy of the Licence at: https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
//
// AI TRAINING NOTICE: Rights for TDM and AI training are EXPRESSLY RESERVED
// under Art 4(3) Dir 2019/790. AI training constitutes a Derivative Work.
// See LICENCE file in the repository root for full details.
//
//
// This software is provided "AS IS", WITHOUT WARRANTY OF ANY KIND.
// See the Licence for the specific language governing permissions and limitations.

// Imports ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
import gleam/bit_array
import gleam/list
import gleam/pair
import gleam/result
import gleam/string

// Message carrier types ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
/// A signed messages' bits, the message within is decodable, but it's signature must still be verified before executing
/// it.
pub type PoliteMessageSignedBits {
  PoliteMessageSignedBits(
    actor: BitArray,
    message: BitArray,
    signature: BitArray,
  )
}

/// After verifying and decoding [`PoliteMessageSignedBits`](#PoliteMessageSignedBits), you can construct it into this.
pub type PoliteMessageVerified {
  PoliteMessageVerified(
    actor: BitArray,
    message: PoliteMessage,
    source: #(BitArray, BitArray),
  )
}

/// Messages send by certain `actors`, which in this case are always the owner of a `did:lumina:`.
/// They can be [`to_bits()`](#to_bits)'ed into a BitArray, then signed into a [`SignedMessage`](#SignedMessage)
/// and then packaged for sending or serving.
///
/// Normally a message signed with a delegated key is packaged with it's `Appoint`, so that a receiving
/// instance immediately knows this message was authored.
/// A _privileged message_ is a message only to be signed with the master key.
///
/// Most message types are user messages, but infrastructural messages also exist. An _infrastructural message_ has an
/// instance as it's actor. The instance signs these message with it's own keypair, of which the public key is available
/// on `/_lumina/lookup/instance/key`. To accomodate this, all infrastructural messages carry their origin as first field.
pub type PoliteMessage {
  /// Grants a certain key a certain scope of rights.
  ///
  /// _This is a privileged user message._
  Appoint(
    pubkey: BitArray,
    scope: SubkeyScope,
    expires_after: Int,
    creation: Int,
  )

  /// A request for immediate invalidation of all data surrounding
  /// this actor and it's other messages. This permanently (unless
  /// successfully defederated) 'deletes' an account, it's did should
  /// never be used again.
  ///
  /// _This is a privileged user message._
  Dissolve

  /// Announces the actor, this places them on an instance, makes them
  /// easier to lookup, and visible over gossip. This is also served from
  /// the `/_lumina/lookup/user/who/<did>` endpoint, along with all the `Appoint`s
  ///
  /// New AnnounceMe messages are made when for example a user changes their instance, or set a new displayname.
  ///
  /// _This is a user message_
  AnnounceMe(
    /// Instance name (domain name) this actor lives on.
    instance: InstanceName,
    /// Username for this actor.
    alias: UserAlias,
    /// Displayname for this actor, limited to 400 grapheme clusters.
    displayname: String,
    /// Moment of creation of this AnnounceMe message, not when this actor was created.
    creation: Int,
  )

  /// A looking message is added to the instance portfolio when the instance is missing a resource.
  ///
  /// _This is an infrastructural message_
  Looking(origin: InstanceName, subtype: Looking)
  /// A got message can be posted into `/_lumina/posted/messages` and posted onto the gossip portfolio.
  /// If the requested resource is a message, the message will be posted directly, and no Got message needs be created.
  ///
  /// _This is an infrastructural message_
  Got(origin: InstanceName, for: Looking)
}

/// A looking message is added to the instance portfolio when the instance is missing a resource.
/// Any instance getting a Looking message has two options:
/// - They don't have the resource, and instead forward the message into their gossip portfolio, adding their own as well.
/// - They have it! And send either a `Got` message back to the origin (or in case of in-band requested resources, post
/// 	 the message itself) and onto their gossip portfolio.
pub type Looking {
  /// `LookingMedia` specifically searches for a media file, media files are never send over the wire, that wouldn't be
  /// polite. Instead they are content-addressed by a SHA-256 hash. The got message for this message
  LookingMedia(media: BitArray, mime: String)
}

/// Scopes to which a subkey can have access.
pub type SubkeyScope {
  /// Most common usage, this is a subkey meant for signing messages on the actor's behalf.
  Delegate
  /// This public key belongs to an actor, and that
  /// actor and all it's delegate keys are now allowed to write any unprivileged message on the managed actor's behalf.
  /// This may be used for bots or organisational accounts.
  Managed
}

/// Returned when an error occurrs within one of Lumina's polite message helpers
pub type Error {
  /// The message being decoded does not have the expected shape.
  UnrecognisedMessage(tag: Int)
  /// The [`Appoint`](#PoliteMessage) scope defined does not exist.
  ScopeDoesNotExist(numbered: Int)
  /// Tried decoding or packaging an invalid message.
  InvalidMessage
  /// Tried packaging or encoding a public key of a size different than 32 bytes.
  PubkeyWithWrongSize
  /// The message signature being packaged is of a size different than 64 bytes.
  SignageWithWrongSize
  /// While unzipping a badge of messages, got another number of packages than advertised.
  WrongNumberOfMessages(expected: Int, got: Int)
  /// While unzipping a bage of messages, the bytes did not line up correctly to shape an array of messages.
  UnalignedBadge
  /// Tried unpacking a package or badge of packages that did not meet expected shape.
  MalformedPackage
  /// An instance name must be a valid domain name, constructing an instance name from a string may fail if this string
  /// exceeds 254 grapheme clusters.
  InstanceNameTooLong
  /// Instance name may not be empty.
  InstanceNameEmpty
  /// Instance name must have a valid domain name format.
  InvalidDomainFormat
  /// Instance name must have valid domain name label length
  InvalidLabelLength
  /// Input contained invalid characters.
  InvalidCharacters
  /// User alias (username) is 25 characters or longer.
  UserAliasTooLong
  UserAliasContainsInvalidCharacters
  DisplayNameTooLong
}

// Functions ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
/// Packages one or more signed messages into a single `BitArray`, ready to transfer or serve.
pub fn package(
  from_message from: List(PoliteMessageSignedBits),
) -> Result(BitArray, Error) {
  use packages <- result.map(
    from
    |> list.map(fn(from) {
      let PoliteMessageSignedBits(actor:, message:, signature: signed) = from

      case bit_array.byte_size(actor), bit_array.byte_size(signed) {
        32, 64 -> Ok(<<actor:bits, signed:bits, message:bits>>)

        _, 64 -> Error(PubkeyWithWrongSize)

        32, _ -> Error(SignageWithWrongSize)
        _, _ -> Error(InvalidMessage)
      }
    })
    |> result.all,
  )
  case packages {
    [] -> <<>>
    [message] -> <<1:16, message:bits>>
    messages -> {
      <<
        list.length(messages):16,
        list.fold(messages, <<>>, fn(acc, message) {
          <<acc:bits, bit_array.byte_size(message):32, message:bits>>
        }):bits,
      >>
    }
  }
}

/// Unpackages a signed message or a badge of signed messages
pub fn unpackage(
  payload payload: BitArray,
) -> Result(List(PoliteMessageSignedBits), Error) {
  case payload {
    <<1:16, actor:bytes-size(32), signed:bytes-size(64), message:bits>> -> {
      [PoliteMessageSignedBits(actor:, message:, signature: signed)] |> Ok
    }
    <<n:16, and:bits>> -> {
      use packages <- result.try(unpackage_loop([], from: and))
      let got = list.length(packages)
      case n == got {
        True -> Ok(packages)
        False -> Error(WrongNumberOfMessages(expected: n, got:))
      }
    }
    _ -> Error(MalformedPackage)
  }
}

fn unpackage_loop(
  unzipped: List(BitArray),
  from from: BitArray,
) -> Result(List(PoliteMessageSignedBits), Error) {
  case from {
    <<len:32, this:bytes-size(len), rest:bits>> ->
      unpackage_loop([this, ..unzipped], rest)
    <<>> ->
      list.reverse(unzipped)
      |> list.map(fn(pkg) {
        case pkg {
          <<1:16, actor:bytes-size(32), signed:bytes-size(64), message:bits>> ->
            Ok(PoliteMessageSignedBits(actor:, message:, signature: signed))

          _ -> Error(UnalignedBadge)
        }
      })
      |> result.all
    _ -> Error(UnalignedBadge)
  }
}

/// Takes a message in `BitArray` form coming from [`to_bits`](#to_bits) or from [`unpackage`](#unpackage) and turns it
/// into a [`PoliteMessage`](#PoliteMessage) type.
pub fn from_bits(payload: BitArray) -> Result(PoliteMessage, Error) {
  case payload {
    <<
      0x00,
      0x01,
      pubkey:bytes-size(32),
      scope_int:size(8),
      expires_after:64,
      creation:64,
    >> -> {
      use target <- result.map(case scope_int {
        1 -> Ok(Delegate)
        2 -> Ok(Managed)
        numbered -> Error(ScopeDoesNotExist(numbered:))
      })
      Appoint(pubkey:, scope: target, expires_after:, creation:)
    }
    <<0x00, 0x02>> -> Ok(Dissolve)

    <<
      0x00,
      0x03,
      instance_len:16,
      instance:bytes-size(instance_len),
      alias_len:16,
      alias:bytes-size(alias_len),
      displayname_len:16,
      displayname:bytes-size(displayname_len),
      creation:64,
    >> -> {
      {
        use instance <- result.try(
          bit_array.to_string(instance)
          |> result.replace_error(InvalidMessage)
          |> result.try(string_to_instance_name),
        )
        use alias <- result.try(
          bit_array.to_string(alias)
          |> result.replace_error(InvalidMessage)
          |> result.try(string_to_user_alias),
        )
        use displayname <- result.try(
          bit_array.to_string(displayname)
          |> result.replace_error(InvalidMessage),
        )

        Ok(AnnounceMe(instance:, alias:, displayname:, creation:))
      }
    }

    <<tag:16, _rest:bits>> -> {
      Error(UnrecognisedMessage(tag:))
    }

    _ -> Error(InvalidMessage)
  }
}

/// Turns a [`PoliteMessage`](#PoliteMessage) into a `BitArray`, suitable for signing, then contructing it into
/// an [`PoliteMessageSignedBits`](#PoliteMessageSignedBits) which can be packaged and sent or served.
pub fn to_bits(message message: PoliteMessage) -> Result(BitArray, Error) {
  case message {
    Appoint(pubkey:, scope:, expires_after:, creation:) -> {
      case bit_array.byte_size(pubkey) {
        32 ->
          <<
            0x00,
            0x01,
            pubkey:bits,
            case scope {
              Delegate -> 1
              Managed -> 2
            }:8,
            expires_after:64,
            creation:64,
          >>
          |> Ok
        _ -> Error(PubkeyWithWrongSize)
      }
    }
    Dissolve -> Ok(<<0x00, 0x02>>)
    AnnounceMe(instance:, alias:, displayname:, creation:) -> {
      case displayname |> string.length() <= 400 {
        True -> {
          let instance = <<instance.name:utf8>>
          let alias = <<alias.username:utf8>>
          let displayname = <<displayname:utf8>>
          <<
            0x00,
            0x03,
            bit_array.byte_size(instance):16,
            instance:bits,
            bit_array.byte_size(alias):16,
            alias:bits,
            bit_array.byte_size(displayname):16,
            displayname:bits,
            creation:64,
          >>
          |> Ok
        }
        False -> Error(DisplayNameTooLong)
      }
    }
    Looking(..) | Got(..) ->
      todo as "Not yet implemented: infrastructural message encoding/decoding."
  }
}

// Helper functions ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

/// Checks to see if message is privileged, and so, should be verified before other messages, and also can only be
/// verified with the actor's main signature.
pub fn is_privileged(message msg: PoliteMessage) -> Bool {
  case msg {
    Appoint(..) | Dissolve -> True
    // We do not use a _ here, we want to be explicit.
    AnnounceMe(..) | Looking(..) | Got(..) -> False
  }
}

/// Checks to see if message in these bytes is privileged, and so, should be verified before other messages, and also can only be
/// verified with the actor's main signature.
///
/// Leaves the non-privileged messages in the second half of the tuple.
pub fn filter_privileged_bits(
  message_bits payload: List(BitArray),
) -> Result(#(List(PoliteMessage), List(BitArray)), Error) {
  list.fold(payload, Ok(#([], [])), fn(tp, bits) {
    use tp <- result.try(tp)
    case
      case bits {
        // These are privileged, and so are immediately decoded.
        // Appoint
        <<0x00, 0x01, _>> -> Ok(True)
        // Dissolve
        <<0x00, 0x02>> -> Ok(True)

        // AnnounceMe
        <<0x00, 0x03, _>> -> Ok(False)

        <<tag:16, _>> -> Error(UnrecognisedMessage(tag:))
        _ -> Error(InvalidMessage)
      }
    {
      Ok(True) ->
        result.map(from_bits(bits), fn(v) {
          pair.map_first(tp, list.prepend(_, this: v))
        })

      Ok(False) -> {
        pair.map_second(tp, list.prepend(_, bits))
        |> Ok
      }
      Error(m) -> Error(m)
    }
  })
}

// Internal helpers ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
fn validate_domain_name_label(label: String) -> Result(Nil, Error) {
  let size = string.byte_size(label)
  case
    { size >= 1 && size <= 63 },
    { string.starts_with(label, "-") || string.ends_with(label, "-") },
    { is_alphanumeric_or_hyphen(string.to_graphemes(label)) }
  {
    False, _, _ -> Error(InvalidLabelLength)
    True, True, _ -> Error(InvalidCharacters)
    True, False, True -> Ok(Nil)
    True, False, False -> Error(InvalidCharacters)
  }
}

fn validate_tld(labels: List(String)) -> Result(Nil, Error) {
  case list.last(labels) {
    Ok(tld) -> {
      case
        string.to_graphemes(tld)
        |> list.all(is_digit)
      {
        True -> Error(InvalidDomainFormat)
        False -> Ok(Nil)
      }
    }
    Error(_) -> Error(InvalidDomainFormat)
  }
}

fn is_alphanumeric_or_hyphen(chars: List(String)) -> Bool {
  list.all(chars, fn(c) { is_lower_alpha(c) || is_digit(c) || c == "-" })
}

fn is_lower_alpha(c: String) -> Bool {
  case c {
    "a"
    | "b"
    | "c"
    | "d"
    | "e"
    | "f"
    | "g"
    | "h"
    | "i"
    | "j"
    | "k"
    | "l"
    | "m"
    | "n"
    | "o"
    | "p"
    | "q"
    | "r"
    | "s"
    | "t"
    | "u"
    | "v"
    | "w"
    | "x"
    | "y"
    | "z" -> True
    _ -> False
  }
}

fn is_digit(c: String) -> Bool {
  case c {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

// Opaque types ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
pub opaque type InstanceName {
  InstanceName(name: String)
}

pub fn string_to_instance_name(str: String) -> Result(InstanceName, Error) {
  case string.lowercase(str) |> string.remove_suffix(".") {
    "" -> Error(InstanceNameEmpty)
    domain ->
      case string.byte_size(domain) <= 253 {
        False -> Error(InstanceNameTooLong)
        True -> {
          let labels = string.split(domain, ".")
          case list.length(labels) >= 2 {
            False -> Error(InvalidDomainFormat)
            True -> {
              use _ <- result.try(list.try_each(
                labels,
                validate_domain_name_label,
              ))
              use _ <- result.try(validate_tld(labels))
              Ok(InstanceName(domain))
            }
          }
        }
      }
  }
}

pub fn instance_name(s: InstanceName) -> String {
  s.name
}

pub opaque type UserAlias {
  UserAlias(username: String)
}

pub fn string_to_user_alias(v) {
  case
    is_alphanumeric_or_hyphen(string.to_graphemes(v)),
    string.length(v) <= 25
  {
    True, True -> Ok(UserAlias(v))
    False, _ -> Error(UserAliasContainsInvalidCharacters)
    _, False -> Error(UserAliasTooLong)
  }
}

pub fn user_alias(s: UserAlias) {
  s.username
}
