component accessors="true" {

    /*====================================
    =            Dependencies            =
    ====================================*/
    property name="builder" inject="provider:QueryBuilder@qb" getter="false" setter="false";
    property name="wirebox" inject="wirebox" getter="false" setter="false";
    property name="str" inject="Str@str" getter="false" setter="false";
    property name="settings" inject="coldbox:modulesettings:quick" getter="false" setter="false";

    /*===========================================
    =            Metadata Properties            =
    ===========================================*/
    property name="entityName";
    property name="mapping";
    property name="fullName";
    property name="table";
    property name="readonly" default="false";
    property name="attributeCasing" default="none";
    property name="key" default="id";
    property name="attributes" default="*";
    property name="metadata";

    /*=====================================
    =            Instance Data            =
    =====================================*/
    property name="attributesData";
    property name="originalAttributes";
    property name="relationships";
    property name="eagerLoad";
    property name="loaded";

    function init() {
        setDefaultProperties();
        return this;
    }

    function setDefaultProperties() {
        setAttributesData( {} );
        setOriginalAttributes( {} );
        setRelationships( {} );
        setEagerLoad( [] );
        setLoaded( false );
    }

    function onDIComplete() {
        metadataInspection();
    }

    /*==================================
    =            Attributes            =
    ==================================*/

    function getKeyValue() {
        return variables.attributesData[ getKey() ];
    }

    function getAttributesData() {
        return duplicate( variables.attributesData );
    }

    function getAttributeNames() {
        return structKeyArray( variables.attributesData );
    }

    function clearAttribute( name, setToNull = false ) {
        if ( setToNull ) {
            variables.attributesData[ applyCasingTransformation( name ) ] = javacast( "null", "" );
        }
        else {
            variables.attributesData.delete( name );
        }
        return this;
    }

    function setAttributesData( attributes ) {
        if ( isNull( arguments.attributes ) ) {
            setLoaded( false );
            variables.attributesData = {};
            return this;
        }
        variables.attributesData = attributes.reduce( function( acc, name, value ) {
            var key = name;
            if ( isColumnAlias( name ) ) {
                key = getColumnForAlias( name );
            }
            acc[ key ] = value;
            return acc;
        }, {} );
        return this;
    }

    function fill( attributes ) {
        for ( var key in attributes ) {
            var value = attributes[ key ];
            if ( isColumnAlias( key ) ) {
                value = getColumnForAlias( key );
            }
            setAttribute( key, attributes[ key ] );
        }
        return this;
    }

    function hasAttribute( name ) {
        return structKeyExists( variables.attributesData, name );
    }

    function isColumnAlias( name ) {
        return ! isSimpleValue( getAttributes() ) &&
            structKeyExists( getAttributes(), name );
    }

    function getColumnForAlias( name ) {
        return getAttributes()[ name ];
    }

    function setOriginalAttributes( attributes ) {
        variables.originalAttributes = duplicate( attributes );
        return this;
    }

    function isDirty() {
        return ! deepEqual( getOriginalAttributes(), getAttributesData() );
    }

    function getAttribute( name ) {
        return variables.attributesData[ name ];
    }

    function setAttribute( name, value ) {
        variables.attributesData[ applyCasingTransformation( name ) ] = value;
        return this;
    }

    /*=====================================
    =            Query Methods            =
    =====================================*/

    function all() {
        return eagerLoadRelations(
            newQuery().from( getTable() ).get()
                .map( function( attributes ) {
                    return newEntity()
                        .setAttributesData( attributes )
                        .setOriginalAttributes( attributes )
                        .setLoaded( true );
                } )
        );
    }

    function get() {
        return eagerLoadRelations(
            getQuery().get().map( function( attributes ) {
                return newEntity()
                    .setAttributesData( attributes )
                    .setOriginalAttributes( attributes )
                    .setLoaded( true );
            } )
        );
    }

    function first() {
        var attributes = getQuery().first();
        return newEntity()
            .setAttributesData( attributes )
            .setOriginalAttributes( attributes )
            .setLoaded( true );
    }

    function find( id ) {
        var data = getQuery()
            .when( ! isSimpleValue( getAttributes() ), function( q ) {
                q.select( arrayMap( structKeyArray( getAttributes() ), function( key ) {
                    return getColumnForAlias( key );
                } ) );
                q.addSelect( getKey() );
            } )
            .from( getTable() )
            .find( id, getKey() );
        if ( structIsEmpty( data ) ) {
            return;
        }
        return newEntity()
            .setAttributesData( data )
            .setOriginalAttributes( data )
            .setLoaded( true );
    }

    function findOrFail( id ) {
        var entity = variables.find( id );
        if ( isNull( entity ) ) {
            throw(
                type = "ModelNotFound",
                message = "No [#getEntityName()#] found with id [#id#]"
            );
        }
        return entity;
    }

    function firstOrFail() {
        var attributes = getQuery().first();
        if ( structIsEmpty( attributes ) ) {
            throw(
                type = "ModelNotFound",
                message = "No [#getEntityName()#] found with constraints [#serializeJSON( getQuery().getBindings() )#]"
            );
        }
        return newEntity()
            .setAttributesData( attributes )
            .setOriginalAttributes( attributes )
            .setLoaded( true );
    }

    function newEntity() {
        return wirebox.getInstance( getFullName() );
    }

    function fresh() {
        return variables.find( getKeyValue() );
    }

    function refresh() {
        setRelationships( {} );
        setAttributesData( newQuery().from( getTable() ).find( getKeyValue(), getKey() ) );
        return this;
    }

    /*===========================================
    =            Persistence Methods            =
    ===========================================*/

    function save() {
        guardReadOnly();
        if ( getLoaded() ) {
            newQuery()
                .where( getKey(), getKeyValue() )
                .update( getAttributesData().map( function( key, value, attributes ) {
                    return isNull( value ) ? { value = "", null = true } : value;
                } ) );
        }
        else {
            var result = newQuery().insert( getAttributesData() );
            var generatedKey = result.keyExists( "generated_key" ) ? result[ "generated_key" ] : result[ "generatedKey" ];
            setAttribute( getKey(), generatedKey );
        }
        setOriginalAttributes( getAttributesData() );
        setLoaded( true );
        return this;
    }

    function delete() {
        guardReadOnly();
        newQuery().delete( getKeyValue(), getKey() );
        return this;
    }

    function update( attributes = {} ) {
        fill( attributes );
        return save();
    }

    function create( attributes = {} ) {
        return newEntity().setAttributesData( attributes ).save();
    }

    function updateAll( attributes = {} ) {
        guardReadOnly();
        getQuery().update( attributes );
        return this;
    }

    function deleteAll( ids = [] ) {
        guardReadOnly();
        if ( ! arrayIsEmpty( ids ) ) {
            newQuery().whereIn( getKey(), ids ).delete();
            return this;
        }

        getQuery().delete();
        return this;
    }

    /*=====================================
    =            Relationships            =
    =====================================*/

    function hasRelationship( name ) {
        return structKeyExists( variables.relationships, name );
    }

    function getRelationship( name ) {
        return variables.relationships[ name ];
    }

    function setRelationship( name, value ) {
        variables.relationships[ name ] = value;
        return this;
    }

    function clearRelationships() {
        variables.relationships = {};
        return this;
    }

    function clearRelationship( name ) {
        variables.relationships.delete( name );
        return this;
    }

    private function belongsTo( relationName, foreignKey ) {
        var related = wirebox.getInstance( relationName );
        if ( isNull( arguments.foreignKey ) ) {
            arguments.foreignKey = lcase( "#related.getEntityName()#_#related.getKey()#" );
        }
        if ( isNull( arguments.owningKey ) ) {
            arguments.owningKey = related.getKey();
        }
        return wirebox.getInstance( name = "BelongsTo@quick", initArguments = {
            related = related,
            relationName = relationName,
            relationMethodName = lcase( callStackGet()[ 2 ][ "Function" ] ),
            owning = this,
            foreignKey = foreignKey,
            foreignKeyValue = hasAttribute( arguments.foreignKey ) ? getAttribute( arguments.foreignKey ) : "",
            owningKey = owningKey
        } );
    }

    private function hasOne( relationName, foreignKey ) {
        var related = wirebox.getInstance( relationName );
        if ( isNull( arguments.foreignKey ) ) {
            arguments.foreignKey = getKey();
        }
        if ( isNull( arguments.owningKey ) ) {
            arguments.owningKey = lcase( "#getEntityName()#_#getKey()#" );
        }
        return wirebox.getInstance( name = "HasOne@quick", initArguments = {
            related = related,
            relationName = relationName,
            relationMethodName = lcase( callStackGet()[ 2 ][ "Function" ] ),
            owning = this,
            foreignKey = foreignKey,
            foreignKeyValue = getKeyValue(),
            owningKey = owningKey
        } );
    }

    private function hasMany( relationName, foreignKey ) {
        var related = wirebox.getInstance( relationName );
        if ( isNull( arguments.foreignKey ) ) {
            arguments.foreignKey = lcase( "#getEntityName()#_#getKey()#" );
        }
        if ( isNull( arguments.owningKey ) ) {
            arguments.owningKey = "#getEntityName()#_#getKey()#";
        }
        return wirebox.getInstance( name = "HasMany@quick", initArguments = {
            related = related,
            relationName = relationName,
            relationMethodName = lcase( callStackGet()[ 2 ][ "Function" ] ),
            owning = this,
            foreignKey = foreignKey,
            foreignKeyValue = getKeyValue(),
            owningKey = owningKey
        } );
    }

    private function belongsToMany( relationName, table, foreignKey, relatedKey ) {
        var related = wirebox.getInstance( relationName );
        if ( isNull( arguments.table ) ) {
            if ( compareNoCase( related.getTable(), getTable() ) < 0 ) {
                arguments.table = lcase( "#related.getTable()#_#getTable()#" );
            }
            else {
                arguments.table = lcase( "#getTable()#_#related.getTable()#" );
            }
        }
        if ( isNull( arguments.relatedKey ) ) {
            arguments.relatedKey = lcase( "#related.getEntityName()#_#related.getKey()#" );
        }
        if ( isNull( arguments.foreignKey ) ) {
            arguments.foreignKey = "#getEntityName()#_#getKey()#";

        }
        return wirebox.getInstance( name = "BelongsToMany@quick", initArguments = {
            related = related,
            relationName = relationName,
            relationMethodName = lcase( callStackGet()[ 2 ][ "Function" ] ),
            owning = this,
            table = table,
            foreignKey = foreignKey,
            foreignKeyValue = getKeyValue(),
            relatedKey = relatedKey
        } );
    }

    private function hasManyThrough( relationName, intermediateName, foreignKey, intermediateKey, owningKey ) {
        var related = wirebox.getInstance( relationName );
        var intermediate = wirebox.getInstance( intermediateName );
        if ( isNull( arguments.intermediateKey ) ) {
            arguments.intermediateKey = lcase( "#intermediate.getEntityName()#_#intermediate.getKey()#" );
        }
        if ( isNull( arguments.foreignKey ) ) {
            arguments.foreignKey = lcase( "#getEntityName()#_#getKey()#" );
        }
        if ( isNull( arguments.owningKey ) ) {
            arguments.owningKey = getKey();
        }
        return wirebox.getInstance( name = "HasManyThrough@quick", initArguments = {
            related = related,
            relationName = relationName,
            relationMethodName = lcase( callStackGet()[ 2 ][ "Function" ] ),
            owning = this,
            intermediate = intermediate,
            foreignKey = foreignKey,
            foreignKeyValue = getKeyValue(),
            intermediateKey = intermediateKey,
            owningKey = owningKey
        } );
    }

    private function polymorphicHasMany( relationName, prefix ) {
        var related = wirebox.getInstance( relationName );
        return wirebox.getInstance( name = "PolymorphicHasMany@quick", initArguments = {
            related = related,
            relationName = relationName,
            relationMethodName = lcase( callStackGet()[ 2 ][ "Function" ] ),
            owning = this,
            foreignKey = "",
            foreignKeyValue = "",
            owningKey = "",
            prefix = prefix
        } );
    }

    private function polymorphicBelongsTo( prefix ) {
        var relationName = getAttribute( "#prefix#_type" );
        var related = wirebox.getInstance( relationName );
        return wirebox.getInstance( name = "PolymorphicBelongsTo@quick", initArguments = {
            related = related,
            relationName = relationName,
            relationMethodName = lcase( callStackGet()[ 2 ][ "Function" ] ),
            owning = this,
            foreignKey = related.getKey(),
            foreignKeyValue = getAttribute( "#prefix#_id" ),
            owningKey = "",
            prefix = prefix
        } );
    }

    function with( relationName ) {
        arrayAppend( variables.eagerLoad, relationName );
        return this;
    }

    private function eagerLoadRelations( entities ) {
        if ( entities.empty() || arrayIsEmpty( variables.eagerLoad ) ) {
            return entities;
        }

        arrayEach( variables.eagerLoad, function( relationName ) {
            entities = eagerLoadRelation( relationName, entities );
        } );

        return entities;
    }

    private function eagerLoadRelation( relationName, entities ) {
        var keys = entities.map( function( entity ) {
            return invoke( entity, relationName ).getForeignKeyValue();
        } ).unique();
        var relatedEntity = invoke( entities.get( 1 ), relationName ).getRelated();
        var owningKey = invoke( entities.get( 1 ), relationName ).getOwningKey();
        var relations = relatedEntity.whereIn( owningKey, keys.get() ).get();

        return matchRelations( entities, relations, relationName );
    }

    private function matchRelations( entities, relations, relationName ) {
        var relationship = invoke( entities.get( 1 ), relationName );
        var groupedRelations = relations.groupBy( key = relationship.getOwningKey(), forceLookup = true );
        return entities.each( function( entity ) {
            var relationship = invoke( entity, relationName );
            if ( structKeyExists( groupedRelations, relationship.getForeignKeyValue() ) ) {
                entity.setRelationship( relationName, groupedRelations[ relationship.getForeignKeyValue() ] );
            }
            else {
                entity.setRelationship( relationName, relationship.getDefaultValue() );
            }
        } );
    }

    /*=======================================
    =            QB Utilities            =
    =======================================*/

    private function newQuery() {
        variables.query = builder.get().from( getTable() );
        return variables.query;
    }

    private function getQuery() {
        param variables.query = builder.get().from( getTable() );
        return variables.query;
    }

    /*=====================================
    =            Magic Methods            =
    =====================================*/

    function onMissingMethod( missingMethodName, missingMethodArguments ) {
        var columnValue = tryColumnName( missingMethodName, missingMethodArguments );
        if ( ! isNull( columnValue ) ) { return columnValue; }
        var q = tryScopes( missingMethodName, missingMethodArguments );
        if ( ! isNull( q ) ) {
            variables.query = q;
            return this;
        }
        var r = tryRelationships( missingMethodName );
        if ( ! isNull( r ) ) { return r; }
        return forwardToQB( missingMethodName, missingMethodArguments );
    }

    private function tryColumnName( missingMethodName, missingMethodArguments ) {
        var getColumnValue = tryColumnGetters( missingMethodName );
        if ( ! isNull( getColumnValue ) ) { return getColumnValue; }
        var setColumnValue = tryColumnSetters( missingMethodName, missingMethodArguments );
        if ( ! isNull( setColumnValue ) ) { return setColumnValue; }
        return;
    }

    private function tryColumnGetters( missingMethodName ) {
        if ( ! str.startsWith( missingMethodName, "get" ) ) {
            return;
        }

        var columnName = applyCasingTransformation(
            str.slice( missingMethodName, 4 )
        );

        if ( isColumnAlias( columnName ) ) {
            return getAttribute( getColumnForAlias( columnName ) );
        }

        if ( hasAttribute( columnName ) ) {
            return getAttribute( columnName );
        }

        return;
    }

    private function tryColumnSetters( missingMethodName, missingMethodArguments ) {
        if ( ! str.startsWith( missingMethodName, "set" ) ) {
            return;
        }

        var columnName = applyCasingTransformation(
            str.slice( missingMethodName, 4 )
        );
        setAttribute( columnName, missingMethodArguments[ 1 ] );
        return missingMethodArguments[ 1 ];
    }

    private function tryRelationships( missingMethodName ) {
        if ( ! str.startsWith( missingMethodName, "get" ) ) {
            return;
        }

        var relationshipName = str.slice( missingMethodName, 4 );
        if ( ! hasRelationship( relationshipName ) ) {
            setRelationship( relationshipName, invoke( this, relationshipName ).retrieve() );
        }

        return getRelationship( relationshipName );
    }

    private function tryScopes( missingMethodName, missingMethodArguments ) {
        if ( structKeyExists( variables, "scope#missingMethodName#" ) ) {
            return invoke( this, "scope#missingMethodName#", {
                builder = getQuery(),
                args = missingMethodArguments
            } );
        }
        return;
    }

    private function forwardToQB( missingMethodName, missingMethodArguments ) {
        var result = invoke( getQuery(), missingMethodName, missingMethodArguments );
        if ( isSimpleValue( result ) ) {
            return result;
        }
        return this;
    }

    function $renderdata() {
        return getAttributesData();
    }

    /*=======================================
    =            Other Utilities            =
    =======================================*/

    private function metadataInspection() {
        var md = getMetadata( this );
        setMetadata( md );
        setFullName( md.fullname );
        param md.mapping = listLast( md.fullname, "." );
        setMapping( md.mapping );
        param md.entityName = listLast( md.name, "." );
        setEntityName( md.entityName );
        param md.table = str.plural( str.snake( getEntityName() ) );
        setTable( md.table );
        param md.readonly = false;
        setReadOnly( md.readonly );
        param md.attributecasing = settings.defaultAttributeCasing;
        setAttributeCasing( md.attributecasing );
        param md.properties = [];
        setAttributesFromProperties( md.properties );
    }

    private function setAttributesFromProperties( properties ) {
        if ( properties.isEmpty() ) {
            return setAttributes( "*" );
        }
        return setAttributes(
            properties.reduce( function( acc, prop ) {
                param prop.column = prop.name;
                param prop.persistent = true;
                if ( prop.persistent ) {
                    acc[ prop.name ] = prop.column;
                }
                return acc;
            }, {} )
        );
    }

    private function applyCasingTransformation( word ) {
        if ( getAttributeCasing() == "none" ) {
            return word;
        }

        return invoke( str, getAttributeCasing(), { 1 = word } );
    }

    private function deepEqual( required expected, required actual ) {
        // Numerics
        if (
            isNumeric( arguments.actual ) &&
            isNumeric( arguments.expected ) &&
            toString( arguments.actual ) == toString( arguments.expected )
        ) {
            return true;
        }

        // Other Simple values
        if (
            isSimpleValue( arguments.actual ) &&
            isSimpleValue( arguments.expected ) &&
            arguments.actual == arguments.expected
        ) {
            return true;
        }

        // Queries
        if ( isQuery( arguments.actual ) && isQuery( arguments.expected ) ) {
            // Check number of records
            if ( arguments.actual.recordCount != arguments.expected.recordCount ) {
                return false;
            }

            // Get both column lists and sort them the same
            var actualColumnList = listSort( arguments.actual.columnList, "textNoCase" );
            var expectedColumnList = listSort( arguments.expected.columnList, "textNoCase" );

            // Check column lists
            if ( actualColumnList != expectedColumnList ) {
                return false;
            }

            for ( var i = 1; i <= arguments.actual.recordCount; i++ ) {
                for ( var column in listToArray( actualColumnList ) ) {
                    if ( arguments.actual[ column ][ i ] != arguments.expected[ column ][ i ] ) {
                        return false;
                    }
                }
            }

            return true;
        }

        // UDFs
        if (
            isCustomFunction( arguments.actual ) &&
            isCustomFunction( arguments.expected ) &&
            arguments.actual.toString() == arguments.expected.toString()
        ) {
            return true;
        }

        // XML
        if (
            IsXmlDoc( arguments.actual ) &&
            IsXmlDoc( arguments.expected ) &&
            toString( arguments.actual ) == toString( arguments.expected )
        ) {
            return true;
        }

        // Arrays
        if ( isArray( arguments.actual ) && isArray( arguments.expected ) ) {
            if ( arrayLen( arguments.actual ) neq arrayLen( arguments.expected ) ) {
                return false;
            }

            for ( var i = 1; i <= arrayLen( arguments.actual ); i++ ) {
                if ( arrayIsDefined( arguments.actual, i ) && arrayIsDefined( arguments.expected, i ) ) {
                    // check for both nulls
                    if ( isNull( arguments.actual[ i ] ) && isNull( arguments.expected[ i ] ) ) {
                        continue;
                    }
                    // check if one is null mismatch
                    if ( isNull( arguments.actual[ i ] ) || isNull( arguments.expected[ i ] ) ) {
                        return false;
                    }
                    // And make sure they match
                    if ( ! deepEqual( arguments.actual[ i ], arguments.expected[ i ] ) ) {
                        return false;
                    }
                    continue;
                }
                // check if both not defined, then continue to next element
                if ( ! arrayIsDefined( arguments.actual, i ) && ! arrayIsDefined( arguments.expected, i ) ) {
                    continue;
                } else {
                    return false;
                }
            }

            return true;
        }

        // Structs / Object
        if ( isStruct( arguments.actual ) && isStruct( arguments.expected ) ) {

            var actualKeys = listSort( structKeyList( arguments.actual ), "textNoCase" );
            var expectedKeys = listSort( structKeyList( arguments.expected ), "textNoCase" );

            if ( actualKeys != expectedKeys ) {
                return false;
            }

            // Loop over each key
            for ( var key in arguments.actual ) {
                // check for both nulls
                if ( isNull( arguments.actual[ key ] ) && isNull( arguments.expected[ key ] ) ) {
                    continue;
                }
                // check if one is null mismatch
                if ( isNull( arguments.actual[ key ] ) || isNull( arguments.expected[ key ] ) ) {
                    return false;
                }
                // And make sure they match when actual values exist
                if ( ! deepEqual( arguments.actual[ key ], arguments.expected[ key ] ) ) {
                    return false;
                }
            }

            return true;
        }

        return false;
    }

    private function guardReadOnly() {
        if ( isReadOnly() ) {
            throw(
                type = "QuickReadOnlyException",
                message = "[#getEntityName()#] is marked as a read-only entity."
            );
        }
    }

    private function isReadOnly() {
        return getReadOnly();
    }

}
