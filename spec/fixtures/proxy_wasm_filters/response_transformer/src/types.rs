use std::convert::TryFrom;
use std::fmt;

use serde::Deserialize;

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct InvalidHeader(String);

impl fmt::Display for InvalidHeader {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "Invalid <header>:<name> => {}", self.0)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(try_from = "String")]
pub(crate) struct KeyValuePair(pub(crate) String, pub(crate) String);

impl TryFrom<String> for KeyValuePair {
    type Error = InvalidHeader;

    fn try_from(input: String) -> std::result::Result<Self, Self::Error> {
        input
            .split_once(':')
            .filter(|(name, value)| {
                name.len() > 0 && value.len() > 0
            })
            .ok_or_else(|| InvalidHeader(input.clone()))
            .and_then(|(name, value)| {
                Ok(KeyValuePair(name.to_string(), value.to_string()))
            })
    }
}

impl TryFrom<&str> for KeyValuePair {
    type Error = InvalidHeader;

    fn try_from(value: &str) -> std::result::Result<Self, Self::Error> {
        KeyValuePair::try_from(value.to_string())
    }
}

#[derive(Deserialize, Debug, PartialEq, Eq, Clone)]
pub(crate) struct Transformations<T = KeyValuePair> {
    pub(crate) headers: Vec<T>,
}

impl<T> Default for Transformations<T> {
    fn default() -> Self {
        Transformations { headers: vec![] }
    }
}

#[derive(Deserialize, Default, PartialEq, Eq, Debug, Clone)]
#[serde(default)]
pub(crate) struct Config {
    pub(crate) remove: Transformations<String>,
    pub(crate) rename: Transformations,
    pub(crate) replace: Transformations,
    pub(crate) add: Transformations,
    pub(crate) append: Transformations,
}

#[cfg(test)]
mod tests {
    use super::*;

    use serde_json;

    impl KeyValuePair {
        #[warn(unused)]
        pub(crate) fn new<T: std::string::ToString>(name: T, value: T) -> Self {
            KeyValuePair(name.to_string(), value.to_string())
        }
    }


    #[test]
    fn test_header_try_from_valid() {
        assert_eq!(Ok(KeyValuePair::new("a", "b")), KeyValuePair::try_from("a:b"));
    }

    #[test]
    fn test_header_try_from_invalid() {
        assert_eq!(Err(InvalidHeader("a".to_string())), KeyValuePair::try_from("a"));
        assert_eq!(Err(InvalidHeader("a:".to_string())), KeyValuePair::try_from("a:"));
        assert_eq!(Err(InvalidHeader(":b".to_string())), KeyValuePair::try_from(":b"));
    }

    #[test]
    fn test_json_deserialize_transformations() {
        assert_eq!(
            Transformations {
                headers: vec![KeyValuePair::new("a", "b"), KeyValuePair::new("c", "d")]
            },
            serde_json::from_str(r#"{ "headers": ["a:b", "c:d"] }"#).unwrap()
        );
    }
}
