return [[
{
    "__schema": {
      "types": [
        {
          "kind": "OBJECT",
          "name": "Query",
          "ofType": null,
          "fields": [
            {
              "name": "allFilms",
              "args": [
                {
                  "name": "after",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "first",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                },
                {
                  "name": "before",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "last",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "FilmsConnection",
                "ofType": null
              }
            },
            {
              "name": "film",
              "args": [
                {
                  "name": "id",
                  "type": {
                    "kind": "SCALAR",
                    "name": "ID",
                    "ofType": null
                  }
                },
                {
                  "name": "filmID",
                  "type": {
                    "kind": "SCALAR",
                    "name": "ID",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "Film",
                "ofType": null
              }
            },
            {
              "name": "allPeople",
              "args": [
                {
                  "name": "after",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "first",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                },
                {
                  "name": "before",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "last",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "PeopleConnection",
                "ofType": null
              }
            },
            {
              "name": "person",
              "args": [
                {
                  "name": "id",
                  "type": {
                    "kind": "SCALAR",
                    "name": "ID",
                    "ofType": null
                  }
                },
                {
                  "name": "personID",
                  "type": {
                    "kind": "SCALAR",
                    "name": "ID",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "Person",
                "ofType": null
              }
            },
            {
              "name": "allPlanets",
              "args": [
                {
                  "name": "after",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "first",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                },
                {
                  "name": "before",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "last",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "PlanetsConnection",
                "ofType": null
              }
            },
            {
              "name": "planet",
              "args": [
                {
                  "name": "id",
                  "type": {
                    "kind": "SCALAR",
                    "name": "ID",
                    "ofType": null
                  }
                },
                {
                  "name": "planetID",
                  "type": {
                    "kind": "SCALAR",
                    "name": "ID",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "Planet",
                "ofType": null
              }
            },
            {
              "name": "allSpecies",
              "args": [
                {
                  "name": "after",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "first",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                },
                {
                  "name": "before",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "last",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "SpeciesConnection",
                "ofType": null
              }
            },
            {
              "name": "species",
              "args": [
                {
                  "name": "id",
                  "type": {
                    "kind": "SCALAR",
                    "name": "ID",
                    "ofType": null
                  }
                },
                {
                  "name": "speciesID",
                  "type": {
                    "kind": "SCALAR",
                    "name": "ID",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "Species",
                "ofType": null
              }
            },
            {
              "name": "allStarships",
              "args": [
                {
                  "name": "after",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "first",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                },
                {
                  "name": "before",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "last",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "StarshipsConnection",
                "ofType": null
              }
            },
            {
              "name": "starship",
              "args": [
                {
                  "name": "id",
                  "type": {
                    "kind": "SCALAR",
                    "name": "ID",
                    "ofType": null
                  }
                },
                {
                  "name": "starshipID",
                  "type": {
                    "kind": "SCALAR",
                    "name": "ID",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "Starship",
                "ofType": null
              }
            },
            {
              "name": "allVehicles",
              "args": [
                {
                  "name": "after",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "first",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                },
                {
                  "name": "before",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "last",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "VehiclesConnection",
                "ofType": null
              }
            },
            {
              "name": "vehicle",
              "args": [
                {
                  "name": "id",
                  "type": {
                    "kind": "SCALAR",
                    "name": "ID",
                    "ofType": null
                  }
                },
                {
                  "name": "vehicleID",
                  "type": {
                    "kind": "SCALAR",
                    "name": "ID",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "Vehicle",
                "ofType": null
              }
            },
            {
              "name": "node",
              "args": [
                {
                  "name": "id",
                  "type": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "SCALAR",
                      "name": "ID",
                      "ofType": null
                    }
                  }
                }
              ],
              "type": {
                "kind": "INTERFACE",
                "name": "Node",
                "ofType": null
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "SCALAR",
          "name": "String",
          "ofType": null,
          "fields": null,
          "interfaces": null,
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "SCALAR",
          "name": "Int",
          "ofType": null,
          "fields": null,
          "interfaces": null,
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "FilmsConnection",
          "ofType": null,
          "fields": [
            {
              "name": "pageInfo",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PageInfo",
                  "ofType": null
                }
              }
            },
            {
              "name": "edges",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "FilmsEdge",
                  "ofType": null
                }
              }
            },
            {
              "name": "totalCount",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "films",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Film",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "PageInfo",
          "ofType": null,
          "fields": [
            {
              "name": "hasNextPage",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Boolean",
                  "ofType": null
                }
              }
            },
            {
              "name": "hasPreviousPage",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Boolean",
                  "ofType": null
                }
              }
            },
            {
              "name": "startCursor",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "endCursor",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "SCALAR",
          "name": "Boolean",
          "ofType": null,
          "fields": null,
          "interfaces": null,
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "FilmsEdge",
          "ofType": null,
          "fields": [
            {
              "name": "node",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Film",
                "ofType": null
              }
            },
            {
              "name": "cursor",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "Film",
          "ofType": null,
          "fields": [
            {
              "name": "title",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "episodeID",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "openingCrawl",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "director",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "producers",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            },
            {
              "name": "releaseDate",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "speciesConnection",
              "args": [
                {
                  "name": "after",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "first",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                },
                {
                  "name": "before",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "last",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "FilmSpeciesConnection",
                "ofType": null
              }
            },
            {
              "name": "starshipConnection",
              "args": [
                {
                  "name": "after",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "first",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                },
                {
                  "name": "before",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "last",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "FilmStarshipsConnection",
                "ofType": null
              }
            },
            {
              "name": "vehicleConnection",
              "args": [
                {
                  "name": "after",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "first",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                },
                {
                  "name": "before",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "last",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "FilmVehiclesConnection",
                "ofType": null
              }
            },
            {
              "name": "characterConnection",
              "args": [
                {
                  "name": "after",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "first",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                },
                {
                  "name": "before",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "last",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "FilmCharactersConnection",
                "ofType": null
              }
            },
            {
              "name": "planetConnection",
              "args": [
                {
                  "name": "after",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "first",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                },
                {
                  "name": "before",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "last",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "FilmPlanetsConnection",
                "ofType": null
              }
            },
            {
              "name": "created",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "edited",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "id",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "ID",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [
            {
              "name": "Node"
            }
          ],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "INTERFACE",
          "name": "Node",
          "ofType": null,
          "fields": [
            {
              "name": "id",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "ID",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": null,
          "possibleTypes": [
            {
              "kind": "OBJECT",
              "name": "Film",
              "ofType": null
            },
            {
              "kind": "OBJECT",
              "name": "Species",
              "ofType": null
            },
            {
              "kind": "OBJECT",
              "name": "Planet",
              "ofType": null
            },
            {
              "kind": "OBJECT",
              "name": "Person",
              "ofType": null
            },
            {
              "kind": "OBJECT",
              "name": "Starship",
              "ofType": null
            },
            {
              "kind": "OBJECT",
              "name": "Vehicle",
              "ofType": null
            }
          ],
          "enumValues": null
        },
        {
          "kind": "SCALAR",
          "name": "ID",
          "ofType": null,
          "fields": null,
          "interfaces": null,
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "FilmSpeciesConnection",
          "ofType": null,
          "fields": [
            {
              "name": "pageInfo",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PageInfo",
                  "ofType": null
                }
              }
            },
            {
              "name": "edges",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "FilmSpeciesEdge",
                  "ofType": null
                }
              }
            },
            {
              "name": "totalCount",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "species",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Species",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "FilmSpeciesEdge",
          "ofType": null,
          "fields": [
            {
              "name": "node",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Species",
                "ofType": null
              }
            },
            {
              "name": "cursor",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "Species",
          "ofType": null,
          "fields": [
            {
              "name": "name",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "classification",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "designation",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "averageHeight",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Float",
                "ofType": null
              }
            },
            {
              "name": "averageLifespan",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "eyeColors",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            },
            {
              "name": "hairColors",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            },
            {
              "name": "skinColors",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            },
            {
              "name": "language",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "homeworld",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Planet",
                "ofType": null
              }
            },
            {
              "name": "personConnection",
              "args": [
                {
                  "name": "after",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "first",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                },
                {
                  "name": "before",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "last",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "SpeciesPeopleConnection",
                "ofType": null
              }
            },
            {
              "name": "filmConnection",
              "args": [
                {
                  "name": "after",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "first",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                },
                {
                  "name": "before",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "last",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "SpeciesFilmsConnection",
                "ofType": null
              }
            },
            {
              "name": "created",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "edited",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "id",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "ID",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [
            {
              "name": "Node"
            }
          ],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "SCALAR",
          "name": "Float",
          "ofType": null,
          "fields": null,
          "interfaces": null,
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "Planet",
          "ofType": null,
          "fields": [
            {
              "name": "name",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "diameter",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "rotationPeriod",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "orbitalPeriod",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "gravity",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "population",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Float",
                "ofType": null
              }
            },
            {
              "name": "climates",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            },
            {
              "name": "terrains",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            },
            {
              "name": "surfaceWater",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Float",
                "ofType": null
              }
            },
            {
              "name": "residentConnection",
              "args": [
                {
                  "name": "after",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "first",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                },
                {
                  "name": "before",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "last",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "PlanetResidentsConnection",
                "ofType": null
              }
            },
            {
              "name": "filmConnection",
              "args": [
                {
                  "name": "after",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "first",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                },
                {
                  "name": "before",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "last",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "PlanetFilmsConnection",
                "ofType": null
              }
            },
            {
              "name": "created",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "edited",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "id",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "ID",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [
            {
              "name": "Node"
            }
          ],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "PlanetResidentsConnection",
          "ofType": null,
          "fields": [
            {
              "name": "pageInfo",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PageInfo",
                  "ofType": null
                }
              }
            },
            {
              "name": "edges",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PlanetResidentsEdge",
                  "ofType": null
                }
              }
            },
            {
              "name": "totalCount",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "residents",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Person",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "PlanetResidentsEdge",
          "ofType": null,
          "fields": [
            {
              "name": "node",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Person",
                "ofType": null
              }
            },
            {
              "name": "cursor",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "Person",
          "ofType": null,
          "fields": [
            {
              "name": "name",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "birthYear",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "eyeColor",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "gender",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "hairColor",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "height",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "mass",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Float",
                "ofType": null
              }
            },
            {
              "name": "skinColor",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "homeworld",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Planet",
                "ofType": null
              }
            },
            {
              "name": "filmConnection",
              "args": [
                {
                  "name": "after",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "first",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                },
                {
                  "name": "before",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "last",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "PersonFilmsConnection",
                "ofType": null
              }
            },
            {
              "name": "species",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Species",
                "ofType": null
              }
            },
            {
              "name": "starshipConnection",
              "args": [
                {
                  "name": "after",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "first",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                },
                {
                  "name": "before",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "last",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "PersonStarshipsConnection",
                "ofType": null
              }
            },
            {
              "name": "vehicleConnection",
              "args": [
                {
                  "name": "after",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "first",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                },
                {
                  "name": "before",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "last",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "PersonVehiclesConnection",
                "ofType": null
              }
            },
            {
              "name": "created",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "edited",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "id",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "ID",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [
            {
              "name": "Node"
            }
          ],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "PersonFilmsConnection",
          "ofType": null,
          "fields": [
            {
              "name": "pageInfo",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PageInfo",
                  "ofType": null
                }
              }
            },
            {
              "name": "edges",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PersonFilmsEdge",
                  "ofType": null
                }
              }
            },
            {
              "name": "totalCount",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "films",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Film",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "PersonFilmsEdge",
          "ofType": null,
          "fields": [
            {
              "name": "node",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Film",
                "ofType": null
              }
            },
            {
              "name": "cursor",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "PersonStarshipsConnection",
          "ofType": null,
          "fields": [
            {
              "name": "pageInfo",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PageInfo",
                  "ofType": null
                }
              }
            },
            {
              "name": "edges",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PersonStarshipsEdge",
                  "ofType": null
                }
              }
            },
            {
              "name": "totalCount",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "starships",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Starship",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "PersonStarshipsEdge",
          "ofType": null,
          "fields": [
            {
              "name": "node",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Starship",
                "ofType": null
              }
            },
            {
              "name": "cursor",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "Starship",
          "ofType": null,
          "fields": [
            {
              "name": "name",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "model",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "starshipClass",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "manufacturers",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            },
            {
              "name": "costInCredits",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Float",
                "ofType": null
              }
            },
            {
              "name": "length",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Float",
                "ofType": null
              }
            },
            {
              "name": "crew",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "passengers",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "maxAtmospheringSpeed",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "hyperdriveRating",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Float",
                "ofType": null
              }
            },
            {
              "name": "MGLT",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "cargoCapacity",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Float",
                "ofType": null
              }
            },
            {
              "name": "consumables",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "pilotConnection",
              "args": [
                {
                  "name": "after",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "first",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                },
                {
                  "name": "before",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "last",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "StarshipPilotsConnection",
                "ofType": null
              }
            },
            {
              "name": "filmConnection",
              "args": [
                {
                  "name": "after",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "first",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                },
                {
                  "name": "before",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "last",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "StarshipFilmsConnection",
                "ofType": null
              }
            },
            {
              "name": "created",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "edited",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "id",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "ID",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [
            {
              "name": "Node"
            }
          ],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "StarshipPilotsConnection",
          "ofType": null,
          "fields": [
            {
              "name": "pageInfo",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PageInfo",
                  "ofType": null
                }
              }
            },
            {
              "name": "edges",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "StarshipPilotsEdge",
                  "ofType": null
                }
              }
            },
            {
              "name": "totalCount",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "pilots",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Person",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "StarshipPilotsEdge",
          "ofType": null,
          "fields": [
            {
              "name": "node",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Person",
                "ofType": null
              }
            },
            {
              "name": "cursor",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "StarshipFilmsConnection",
          "ofType": null,
          "fields": [
            {
              "name": "pageInfo",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PageInfo",
                  "ofType": null
                }
              }
            },
            {
              "name": "edges",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "StarshipFilmsEdge",
                  "ofType": null
                }
              }
            },
            {
              "name": "totalCount",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "films",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Film",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "StarshipFilmsEdge",
          "ofType": null,
          "fields": [
            {
              "name": "node",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Film",
                "ofType": null
              }
            },
            {
              "name": "cursor",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "PersonVehiclesConnection",
          "ofType": null,
          "fields": [
            {
              "name": "pageInfo",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PageInfo",
                  "ofType": null
                }
              }
            },
            {
              "name": "edges",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PersonVehiclesEdge",
                  "ofType": null
                }
              }
            },
            {
              "name": "totalCount",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "vehicles",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Vehicle",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "PersonVehiclesEdge",
          "ofType": null,
          "fields": [
            {
              "name": "node",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Vehicle",
                "ofType": null
              }
            },
            {
              "name": "cursor",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "Vehicle",
          "ofType": null,
          "fields": [
            {
              "name": "name",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "model",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "vehicleClass",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "manufacturers",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            },
            {
              "name": "costInCredits",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Float",
                "ofType": null
              }
            },
            {
              "name": "length",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Float",
                "ofType": null
              }
            },
            {
              "name": "crew",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "passengers",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "maxAtmospheringSpeed",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "cargoCapacity",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Float",
                "ofType": null
              }
            },
            {
              "name": "consumables",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "pilotConnection",
              "args": [
                {
                  "name": "after",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "first",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                },
                {
                  "name": "before",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "last",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "VehiclePilotsConnection",
                "ofType": null
              }
            },
            {
              "name": "filmConnection",
              "args": [
                {
                  "name": "after",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "first",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                },
                {
                  "name": "before",
                  "type": {
                    "kind": "SCALAR",
                    "name": "String",
                    "ofType": null
                  }
                },
                {
                  "name": "last",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Int",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "OBJECT",
                "name": "VehicleFilmsConnection",
                "ofType": null
              }
            },
            {
              "name": "created",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "edited",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "id",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "ID",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [
            {
              "name": "Node"
            }
          ],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "VehiclePilotsConnection",
          "ofType": null,
          "fields": [
            {
              "name": "pageInfo",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PageInfo",
                  "ofType": null
                }
              }
            },
            {
              "name": "edges",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "VehiclePilotsEdge",
                  "ofType": null
                }
              }
            },
            {
              "name": "totalCount",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "pilots",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Person",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "VehiclePilotsEdge",
          "ofType": null,
          "fields": [
            {
              "name": "node",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Person",
                "ofType": null
              }
            },
            {
              "name": "cursor",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "VehicleFilmsConnection",
          "ofType": null,
          "fields": [
            {
              "name": "pageInfo",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PageInfo",
                  "ofType": null
                }
              }
            },
            {
              "name": "edges",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "VehicleFilmsEdge",
                  "ofType": null
                }
              }
            },
            {
              "name": "totalCount",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "films",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Film",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "VehicleFilmsEdge",
          "ofType": null,
          "fields": [
            {
              "name": "node",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Film",
                "ofType": null
              }
            },
            {
              "name": "cursor",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "PlanetFilmsConnection",
          "ofType": null,
          "fields": [
            {
              "name": "pageInfo",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PageInfo",
                  "ofType": null
                }
              }
            },
            {
              "name": "edges",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PlanetFilmsEdge",
                  "ofType": null
                }
              }
            },
            {
              "name": "totalCount",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "films",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Film",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "PlanetFilmsEdge",
          "ofType": null,
          "fields": [
            {
              "name": "node",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Film",
                "ofType": null
              }
            },
            {
              "name": "cursor",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "SpeciesPeopleConnection",
          "ofType": null,
          "fields": [
            {
              "name": "pageInfo",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PageInfo",
                  "ofType": null
                }
              }
            },
            {
              "name": "edges",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "SpeciesPeopleEdge",
                  "ofType": null
                }
              }
            },
            {
              "name": "totalCount",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "people",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Person",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "SpeciesPeopleEdge",
          "ofType": null,
          "fields": [
            {
              "name": "node",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Person",
                "ofType": null
              }
            },
            {
              "name": "cursor",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "SpeciesFilmsConnection",
          "ofType": null,
          "fields": [
            {
              "name": "pageInfo",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PageInfo",
                  "ofType": null
                }
              }
            },
            {
              "name": "edges",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "SpeciesFilmsEdge",
                  "ofType": null
                }
              }
            },
            {
              "name": "totalCount",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "films",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Film",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "SpeciesFilmsEdge",
          "ofType": null,
          "fields": [
            {
              "name": "node",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Film",
                "ofType": null
              }
            },
            {
              "name": "cursor",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "FilmStarshipsConnection",
          "ofType": null,
          "fields": [
            {
              "name": "pageInfo",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PageInfo",
                  "ofType": null
                }
              }
            },
            {
              "name": "edges",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "FilmStarshipsEdge",
                  "ofType": null
                }
              }
            },
            {
              "name": "totalCount",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "starships",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Starship",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "FilmStarshipsEdge",
          "ofType": null,
          "fields": [
            {
              "name": "node",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Starship",
                "ofType": null
              }
            },
            {
              "name": "cursor",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "FilmVehiclesConnection",
          "ofType": null,
          "fields": [
            {
              "name": "pageInfo",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PageInfo",
                  "ofType": null
                }
              }
            },
            {
              "name": "edges",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "FilmVehiclesEdge",
                  "ofType": null
                }
              }
            },
            {
              "name": "totalCount",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "vehicles",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Vehicle",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "FilmVehiclesEdge",
          "ofType": null,
          "fields": [
            {
              "name": "node",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Vehicle",
                "ofType": null
              }
            },
            {
              "name": "cursor",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "FilmCharactersConnection",
          "ofType": null,
          "fields": [
            {
              "name": "pageInfo",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PageInfo",
                  "ofType": null
                }
              }
            },
            {
              "name": "edges",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "FilmCharactersEdge",
                  "ofType": null
                }
              }
            },
            {
              "name": "totalCount",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "characters",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Person",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "FilmCharactersEdge",
          "ofType": null,
          "fields": [
            {
              "name": "node",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Person",
                "ofType": null
              }
            },
            {
              "name": "cursor",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "FilmPlanetsConnection",
          "ofType": null,
          "fields": [
            {
              "name": "pageInfo",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PageInfo",
                  "ofType": null
                }
              }
            },
            {
              "name": "edges",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "FilmPlanetsEdge",
                  "ofType": null
                }
              }
            },
            {
              "name": "totalCount",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "planets",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Planet",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "FilmPlanetsEdge",
          "ofType": null,
          "fields": [
            {
              "name": "node",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Planet",
                "ofType": null
              }
            },
            {
              "name": "cursor",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "PeopleConnection",
          "ofType": null,
          "fields": [
            {
              "name": "pageInfo",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PageInfo",
                  "ofType": null
                }
              }
            },
            {
              "name": "edges",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PeopleEdge",
                  "ofType": null
                }
              }
            },
            {
              "name": "totalCount",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "people",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Person",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "PeopleEdge",
          "ofType": null,
          "fields": [
            {
              "name": "node",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Person",
                "ofType": null
              }
            },
            {
              "name": "cursor",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "PlanetsConnection",
          "ofType": null,
          "fields": [
            {
              "name": "pageInfo",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PageInfo",
                  "ofType": null
                }
              }
            },
            {
              "name": "edges",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PlanetsEdge",
                  "ofType": null
                }
              }
            },
            {
              "name": "totalCount",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "planets",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Planet",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "PlanetsEdge",
          "ofType": null,
          "fields": [
            {
              "name": "node",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Planet",
                "ofType": null
              }
            },
            {
              "name": "cursor",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "SpeciesConnection",
          "ofType": null,
          "fields": [
            {
              "name": "pageInfo",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PageInfo",
                  "ofType": null
                }
              }
            },
            {
              "name": "edges",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "SpeciesEdge",
                  "ofType": null
                }
              }
            },
            {
              "name": "totalCount",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "species",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Species",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "SpeciesEdge",
          "ofType": null,
          "fields": [
            {
              "name": "node",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Species",
                "ofType": null
              }
            },
            {
              "name": "cursor",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "StarshipsConnection",
          "ofType": null,
          "fields": [
            {
              "name": "pageInfo",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PageInfo",
                  "ofType": null
                }
              }
            },
            {
              "name": "edges",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "StarshipsEdge",
                  "ofType": null
                }
              }
            },
            {
              "name": "totalCount",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "starships",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Starship",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "StarshipsEdge",
          "ofType": null,
          "fields": [
            {
              "name": "node",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Starship",
                "ofType": null
              }
            },
            {
              "name": "cursor",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "VehiclesConnection",
          "ofType": null,
          "fields": [
            {
              "name": "pageInfo",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "PageInfo",
                  "ofType": null
                }
              }
            },
            {
              "name": "edges",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "VehiclesEdge",
                  "ofType": null
                }
              }
            },
            {
              "name": "totalCount",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Int",
                "ofType": null
              }
            },
            {
              "name": "vehicles",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "Vehicle",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "VehiclesEdge",
          "ofType": null,
          "fields": [
            {
              "name": "node",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "Vehicle",
                "ofType": null
              }
            },
            {
              "name": "cursor",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "__Schema",
          "ofType": null,
          "fields": [
            {
              "name": "types",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "LIST",
                  "name": null,
                  "ofType": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "OBJECT",
                      "name": "__Type",
                      "ofType": null
                    }
                  }
                }
              }
            },
            {
              "name": "queryType",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "__Type",
                  "ofType": null
                }
              }
            },
            {
              "name": "mutationType",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "__Type",
                "ofType": null
              }
            },
            {
              "name": "subscriptionType",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "__Type",
                "ofType": null
              }
            },
            {
              "name": "directives",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "LIST",
                  "name": null,
                  "ofType": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "OBJECT",
                      "name": "__Directive",
                      "ofType": null
                    }
                  }
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "__Type",
          "ofType": null,
          "fields": [
            {
              "name": "kind",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "ENUM",
                  "name": "__TypeKind",
                  "ofType": null
                }
              }
            },
            {
              "name": "name",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "description",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "fields",
              "args": [
                {
                  "name": "includeDeprecated",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Boolean",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "NON_NULL",
                  "name": null,
                  "ofType": {
                    "kind": "OBJECT",
                    "name": "__Field",
                    "ofType": null
                  }
                }
              }
            },
            {
              "name": "interfaces",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "NON_NULL",
                  "name": null,
                  "ofType": {
                    "kind": "OBJECT",
                    "name": "__Type",
                    "ofType": null
                  }
                }
              }
            },
            {
              "name": "possibleTypes",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "NON_NULL",
                  "name": null,
                  "ofType": {
                    "kind": "OBJECT",
                    "name": "__Type",
                    "ofType": null
                  }
                }
              }
            },
            {
              "name": "enumValues",
              "args": [
                {
                  "name": "includeDeprecated",
                  "type": {
                    "kind": "SCALAR",
                    "name": "Boolean",
                    "ofType": null
                  }
                }
              ],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "NON_NULL",
                  "name": null,
                  "ofType": {
                    "kind": "OBJECT",
                    "name": "__EnumValue",
                    "ofType": null
                  }
                }
              }
            },
            {
              "name": "inputFields",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "NON_NULL",
                  "name": null,
                  "ofType": {
                    "kind": "OBJECT",
                    "name": "__InputValue",
                    "ofType": null
                  }
                }
              }
            },
            {
              "name": "ofType",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "__Type",
                "ofType": null
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "ENUM",
          "name": "__TypeKind",
          "ofType": null,
          "fields": null,
          "interfaces": null,
          "possibleTypes": null,
          "enumValues": [
            {
              "name": "SCALAR"
            },
            {
              "name": "OBJECT"
            },
            {
              "name": "INTERFACE"
            },
            {
              "name": "UNION"
            },
            {
              "name": "ENUM"
            },
            {
              "name": "INPUT_OBJECT"
            },
            {
              "name": "LIST"
            },
            {
              "name": "NON_NULL"
            }
          ]
        },
        {
          "kind": "OBJECT",
          "name": "__Field",
          "ofType": null,
          "fields": [
            {
              "name": "name",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            },
            {
              "name": "description",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "args",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "LIST",
                  "name": null,
                  "ofType": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "OBJECT",
                      "name": "__InputValue",
                      "ofType": null
                    }
                  }
                }
              }
            },
            {
              "name": "type",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "__Type",
                  "ofType": null
                }
              }
            },
            {
              "name": "isDeprecated",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Boolean",
                  "ofType": null
                }
              }
            },
            {
              "name": "deprecationReason",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "__InputValue",
          "ofType": null,
          "fields": [
            {
              "name": "name",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            },
            {
              "name": "description",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "type",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "__Type",
                  "ofType": null
                }
              }
            },
            {
              "name": "defaultValue",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "__EnumValue",
          "ofType": null,
          "fields": [
            {
              "name": "name",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            },
            {
              "name": "description",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "isDeprecated",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Boolean",
                  "ofType": null
                }
              }
            },
            {
              "name": "deprecationReason",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "OBJECT",
          "name": "__Directive",
          "ofType": null,
          "fields": [
            {
              "name": "name",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            },
            {
              "name": "description",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              }
            },
            {
              "name": "locations",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "LIST",
                  "name": null,
                  "ofType": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "ENUM",
                      "name": "__DirectiveLocation",
                      "ofType": null
                    }
                  }
                }
              }
            },
            {
              "name": "args",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "LIST",
                  "name": null,
                  "ofType": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "OBJECT",
                      "name": "__InputValue",
                      "ofType": null
                    }
                  }
                }
              }
            }
          ],
          "interfaces": [],
          "possibleTypes": null,
          "enumValues": null
        },
        {
          "kind": "ENUM",
          "name": "__DirectiveLocation",
          "ofType": null,
          "fields": null,
          "interfaces": null,
          "possibleTypes": null,
          "enumValues": [
            {
              "name": "QUERY"
            },
            {
              "name": "MUTATION"
            },
            {
              "name": "SUBSCRIPTION"
            },
            {
              "name": "FIELD"
            },
            {
              "name": "FRAGMENT_DEFINITION"
            },
            {
              "name": "FRAGMENT_SPREAD"
            },
            {
              "name": "INLINE_FRAGMENT"
            },
            {
              "name": "VARIABLE_DEFINITION"
            },
            {
              "name": "SCHEMA"
            },
            {
              "name": "SCALAR"
            },
            {
              "name": "OBJECT"
            },
            {
              "name": "FIELD_DEFINITION"
            },
            {
              "name": "ARGUMENT_DEFINITION"
            },
            {
              "name": "INTERFACE"
            },
            {
              "name": "UNION"
            },
            {
              "name": "ENUM"
            },
            {
              "name": "ENUM_VALUE"
            },
            {
              "name": "INPUT_OBJECT"
            },
            {
              "name": "INPUT_FIELD_DEFINITION"
            }
          ]
        }
      ]
    }
  }
]]
