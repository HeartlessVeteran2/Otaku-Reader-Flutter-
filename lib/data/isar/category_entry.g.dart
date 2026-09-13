// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'category_entry.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetCategoryEntryCollection on Isar {
  IsarCollection<CategoryEntry> get categoryEntrys => this.collection();
}

const CategoryEntrySchema = CollectionSchema(
  name: r'CategoryEntry',
  id: -3013116515174759932,
  properties: {
    r'hidden': PropertySchema(id: 0, name: r'hidden', type: IsarType.bool),
    r'name': PropertySchema(id: 1, name: r'name', type: IsarType.string),
    r'order': PropertySchema(id: 2, name: r'order', type: IsarType.long),
  },

  estimateSize: _categoryEntryEstimateSize,
  serialize: _categoryEntrySerialize,
  deserialize: _categoryEntryDeserialize,
  deserializeProp: _categoryEntryDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},

  getId: _categoryEntryGetId,
  getLinks: _categoryEntryGetLinks,
  attach: _categoryEntryAttach,
  version: '3.3.2',
);

int _categoryEntryEstimateSize(
  CategoryEntry object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.name.length * 3;
  return bytesCount;
}

void _categoryEntrySerialize(
  CategoryEntry object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeBool(offsets[0], object.hidden);
  writer.writeString(offsets[1], object.name);
  writer.writeLong(offsets[2], object.order);
}

CategoryEntry _categoryEntryDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = CategoryEntry();
  object.hidden = reader.readBool(offsets[0]);
  object.id = id;
  object.name = reader.readString(offsets[1]);
  object.order = reader.readLong(offsets[2]);
  return object;
}

P _categoryEntryDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readBool(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _categoryEntryGetId(CategoryEntry object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _categoryEntryGetLinks(CategoryEntry object) {
  return [];
}

void _categoryEntryAttach(
  IsarCollection<dynamic> col,
  Id id,
  CategoryEntry object,
) {
  object.id = id;
}

extension CategoryEntryQueryWhereSort
    on QueryBuilder<CategoryEntry, CategoryEntry, QWhere> {
  QueryBuilder<CategoryEntry, CategoryEntry, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension CategoryEntryQueryWhere
    on QueryBuilder<CategoryEntry, CategoryEntry, QWhereClause> {
  QueryBuilder<CategoryEntry, CategoryEntry, QAfterWhereClause> idEqualTo(
    Id id,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterWhereClause> idNotEqualTo(
    Id id,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterWhereClause> idGreaterThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterWhereClause> idLessThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerId,
          includeLower: includeLower,
          upper: upperId,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension CategoryEntryQueryFilter
    on QueryBuilder<CategoryEntry, CategoryEntry, QFilterCondition> {
  QueryBuilder<CategoryEntry, CategoryEntry, QAfterFilterCondition>
  hiddenEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'hidden', value: value),
      );
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterFilterCondition> idEqualTo(
    Id value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterFilterCondition>
  idGreaterThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'id',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterFilterCondition> nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterFilterCondition>
  nameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterFilterCondition>
  nameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterFilterCondition> nameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'name',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterFilterCondition>
  nameStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterFilterCondition>
  nameEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterFilterCondition>
  nameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterFilterCondition> nameMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'name',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterFilterCondition>
  nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'name', value: ''),
      );
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterFilterCondition>
  nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'name', value: ''),
      );
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterFilterCondition>
  orderEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'order', value: value),
      );
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterFilterCondition>
  orderGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'order',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterFilterCondition>
  orderLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'order',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterFilterCondition>
  orderBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'order',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension CategoryEntryQueryObject
    on QueryBuilder<CategoryEntry, CategoryEntry, QFilterCondition> {}

extension CategoryEntryQueryLinks
    on QueryBuilder<CategoryEntry, CategoryEntry, QFilterCondition> {}

extension CategoryEntryQuerySortBy
    on QueryBuilder<CategoryEntry, CategoryEntry, QSortBy> {
  QueryBuilder<CategoryEntry, CategoryEntry, QAfterSortBy> sortByHidden() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hidden', Sort.asc);
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterSortBy> sortByHiddenDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hidden', Sort.desc);
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterSortBy> sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterSortBy> sortByOrder() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'order', Sort.asc);
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterSortBy> sortByOrderDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'order', Sort.desc);
    });
  }
}

extension CategoryEntryQuerySortThenBy
    on QueryBuilder<CategoryEntry, CategoryEntry, QSortThenBy> {
  QueryBuilder<CategoryEntry, CategoryEntry, QAfterSortBy> thenByHidden() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hidden', Sort.asc);
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterSortBy> thenByHiddenDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hidden', Sort.desc);
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterSortBy> thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterSortBy> thenByOrder() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'order', Sort.asc);
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QAfterSortBy> thenByOrderDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'order', Sort.desc);
    });
  }
}

extension CategoryEntryQueryWhereDistinct
    on QueryBuilder<CategoryEntry, CategoryEntry, QDistinct> {
  QueryBuilder<CategoryEntry, CategoryEntry, QDistinct> distinctByHidden() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'hidden');
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QDistinct> distinctByName({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CategoryEntry, CategoryEntry, QDistinct> distinctByOrder() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'order');
    });
  }
}

extension CategoryEntryQueryProperty
    on QueryBuilder<CategoryEntry, CategoryEntry, QQueryProperty> {
  QueryBuilder<CategoryEntry, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<CategoryEntry, bool, QQueryOperations> hiddenProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'hidden');
    });
  }

  QueryBuilder<CategoryEntry, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<CategoryEntry, int, QQueryOperations> orderProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'order');
    });
  }
}
