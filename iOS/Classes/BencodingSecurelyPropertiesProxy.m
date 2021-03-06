/**
 * Securely Titanium Security Project
 * Copyright (c) 2014 by Benjamin Bahrenburg. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */

#import "BencodingSecurelyPropertiesProxy.h"
#import "BencodingSecurelyModule.h"
#import "PropertyKeyChain.h"
#import "PropertyPList.h"
#import "TiUtils.h"
#import "NSData+CommonCrypto.h"

@implementation BencodingSecurelyPropertiesProxy

-(id)init
{
    if (self = [super init]) {
        //Set a few flags on proxy creation
        _propertyToken = @"BXS.";
        _valuesEncrypted = NO;
        _fieldsEncrypted = NO;
        _keyCacheLimit = 500;
        _keyCache = [[NSMutableDictionary alloc] init];
    }

    return self;
}

-(void)_initWithProperties:(NSDictionary*)properties
{
    NSString *identifier = [TiUtils stringValue:@"identifier" properties:properties];
    NSString *accessGroup = [TiUtils stringValue:@"accessGroup" properties:properties];

    _storageType = [TiUtils intValue:@"storageType" properties:properties def:kBCXKeyChain_Storage];
    _securityLevel = [TiUtils intValue:@"securityLevel" properties:properties def:kBCXProperty_Security_Low];
    _secret = [TiUtils stringValue:@"secret" properties:properties];

    if(_storageType!=kBCXKeyChain_Storage && _storageType!=kBCXKeyChain_Storage){
        NSLog(@"[ERROR] Invalid storageType provided, defaulting to KeyChain Storage");
        _storageType = kBCXKeyChain_Storage;
    }

    if(_storageType==kBCXPLIST_Storage && _securityLevel == kBCXProperty_Security_Low){
         NSLog(@"[ERROR] PLIST Storage required MED or HIGH securityLevel, increasing securityLevel to MED");
        _securityLevel = kBCXProperty_Security_Med;
    }

    if((_securityLevel == kBCXProperty_Security_Med ||
       _securityLevel == kBCXProperty_Security_High ) && _secret == nil){
        NSLog(@"[ERROR] A secret is required for MED and HIGH securityLevel");
        NSLog(@"[ERROR] Since no secret provided BUNDLE ID will be used");
        _secret = [[NSBundle mainBundle] bundleIdentifier];
    }

    if(_securityLevel == kBCXProperty_Security_Med ||
       _securityLevel == kBCXProperty_Security_High ){
        _valuesEncrypted = YES;
    }

    if(_securityLevel == kBCXProperty_Security_High ){
        _fieldsEncrypted = YES;
    }

    if(_storageType == kBCXKeyChain_Storage && identifier == nil){
        NSLog(@"[ERROR] The identifier parameter is required for KeyChain Storage");
        NSLog(@"[ERROR] Since identifier was provided BUNDLE ID will be used");
        identifier = [[NSBundle mainBundle] bundleIdentifier];
    }

    if(_storageType == kBCXKeyChain_Storage){
        _provider = [[PropertyKeyChain alloc] initWithIdentifierAndOptions:identifier
                                                           withAccessGroup:accessGroup
                                                        withEncryptedField:_fieldsEncrypted
                                                        withEncryptedValues:_valuesEncrypted
                                                                withSecret:_secret];
    }

    if(_storageType == kBCXPLIST_Storage){
        _provider = [[PropertyPList alloc] initWithIdentifierAndOptions:_propertyToken
                                                           withAccessGroup:accessGroup
                                                     withEncryptedField:_fieldsEncrypted
                                                    withEncryptedValues:_valuesEncrypted
                                                                withSecret:_secret];
    }

    [super _initWithProperties:properties];
}

#pragma Private methods

-(NSString*)obtainKey:(NSString*)key
{
    return (_fieldsEncrypted) ? [self composeSecret:key] : [_propertyToken stringByAppendingString:key];
}

-(void) manageKeyCache
{
    //Check if we've hit the key cache threshold
    //This should never happen, but added to guard against bad behavior
    if([_keyCache count] > _keyCacheLimit){
        [_keyCache removeAllObjects];
    }
}
-(NSString*)composeSecret:(NSString*)key
{
    [self manageKeyCache];

    //First check if the key is in cache, this avoids
    //having to hash it more often
    if ([_keyCache objectForKey:key]){
        return (NSString*)[_keyCache objectForKey:key];
    }else{
        //Create the seed
        NSString *seed = _secret;
        [seed stringByAppendingString:@"_"];
        [seed stringByAppendingString:key];
        //Do the SHA hash
        NSString* value = [NSString stringWithUTF8String:[[[seed dataUsingEncoding:NSUTF8StringEncoding] SHA512Hash] bytes]];
        //Add the new key into our hash table for faster lookup next time
        [_keyCache setValue:value forKey:key];
        return value;
    }
}

#pragma Event APIs

-(void) triggerEvent:(NSString *)eventName actionType:(NSString *)actionType
{
    if ([self _hasListeners:@"changed"])
    {
        NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:
                               eventName,@"source",
                               eventName,@"propertyName",
                               actionType,@"actionType",
                               nil
                               ];
        
		[self fireEvent:@"changed" withObject:event];
    }
}


#pragma Public APIs

//Allow the user to clear the name cache if they want
-(void)clearNameCache:(id) unused
{
    [_keyCache removeAllObjects];
}

//Set the threshold used in managing the key Cache dictionary
-(void)setNameCacheThreshold:(id) threshold
{
    _keyCacheLimit = [TiUtils intValue:threshold def:500];
    [self manageKeyCache];
}

-(id)getStorageType:(id) unused
{
    return [NSNumber numberWithInt:_storageType];
}

-(id)getSecurityLevel:(id) unused
{
    return [NSNumber numberWithInt:_securityLevel];
}

-(NSNumber*)hasValuesEncrypted: (id) unused
{
    return NUMBOOL(_valuesEncrypted);
}

-(NSNumber*)hasFieldsEncrypted: (id) unused
{
    return NUMBOOL(_fieldsEncrypted);
}

-(BOOL)propertyExists: (NSString *) key
{
    return [_provider propertyExists:[self obtainKey:key]];
}

#define GETSPROP \
ENSURE_TYPE(args,NSArray);\
NSString *key = [args objectAtIndex:0];\
id defaultValue = [args count] > 1 ? [args objectAtIndex:1] : [NSNull null];\
if (![self propertyExists:[self obtainKey:key]]) return defaultValue; \

-(id)getBool:(id)args
{
	GETSPROP
	return[_provider getBool:[self obtainKey:key]];
}

-(id)getDouble:(id)args
{
	GETSPROP
    return[_provider getDouble:[self obtainKey:key]];
}

-(id)getInt:(id)args
{
	GETSPROP
    return[_provider getInt:[self obtainKey:key]];
}

-(NSString *)getString:(id)args
{
    GETSPROP
    return[_provider getString:[self obtainKey:key]];
}

-(id)getList:(id)args
{
	GETSPROP
    return[_provider getList:[self obtainKey:key]];
}

-(id)getObject:(id)args
{
    GETSPROP
    return[_provider getObject:[self obtainKey:key]];
}

-(BOOL)propertyDelta:(id)value withKey:(NSString*)key
{
    if([self propertyExists:[self obtainKey:key]]){
        return (_valuesEncrypted) ? NO : [[_provider objectForKey:[self obtainKey:key]] isEqual:value];
    }else{
        return NO;
    }
}

#define SETSPROP \
ENSURE_TYPE(args,NSArray);\
NSString *key = [args objectAtIndex:0];\
id value = [args count] > 1 ? [args objectAtIndex:1] : nil;\
if (value==nil || value==[NSNull null]) {\
[_provider removeProperty:key];\
return;\
}\
if ([self propertyDelta:value withKey:[self obtainKey:key]]) {\
return;\
}\

-(void)setBool:(id)args
{
	SETSPROP
    [_provider setBool:[TiUtils boolValue:args] withKey:[self obtainKey:key]];
    [self triggerEvent:key actionType:@"modify"];
}

-(void)setDouble:(id)args
{
	SETSPROP
    [_provider setDouble:[TiUtils doubleValue:value] withKey:[self obtainKey:key]];
    [self triggerEvent:key actionType:@"modify"];
}

-(void)setInt:(id)args
{
	SETSPROP
    [_provider setInt:[TiUtils intValue:value] withKey:[self obtainKey:key]];
    [self triggerEvent:key actionType:@"modify"];
}

-(void)setString:(id)args
{    
	SETSPROP
    [_provider setString:[TiUtils stringValue:value] withKey:[self obtainKey:key]];
    [self triggerEvent:key actionType:@"modify"];
}

-(void)setList:(id)args
{
	SETSPROP
    [_provider setList:args withKey:[self obtainKey:key]];
    [self triggerEvent:key actionType:@"modify"];
}

-(void)setObject:(id)args
{
    SETSPROP
    [_provider setObject:args withKey:[self obtainKey:key]];
    [self triggerEvent:key actionType:@"modify"];
}

-(id)hasProperty:(id)key
{
    ENSURE_TYPE(key, NSString);
    return [_provider hasProperty:[self obtainKey:key]];
}

-(void)removeProperty:(id)key
{
	ENSURE_SINGLE_ARG(key,NSString);
    [_provider removeProperty:[self obtainKey:key]];
    [self triggerEvent:key actionType:@"remove"];
}

-(void)removeAllProperties:(id)unused
{
    [_provider removeAllProperties];
    [self triggerEvent:@"NA" actionType:@"removeall"];
}

-(id)listProperties:(id)args
{
    return [_provider listProperties];
}

-(void)setIdentifier:(id)value
{
    NSLog(@"[ERROR] Indentifier needs to be set at creation of the PROXY");
}

-(void)setAccessGroup:(id)value
{
    NSLog(@"[ERROR] Access Group needs to be set at creation of the PROXY");
}
-(void)setSecret:(id)args
{
    NSLog(@"[ERROR] Secret needs to be set at creation of the PROXY");
}
@end
