package scripting;

import flixel.group.FlxGroup.FlxTypedGroup;
import haxe.ds.EnumValueMap;
import haxe.ds.IntMap;
import haxe.ds.ObjectMap;
import haxe.ds.StringMap;

using StringTools;

class DynamicAccesor {
    var obj: Dynamic = null;
    var field: String = null;
    var index: Int = -1;

    public function new() {}

    public function target(obj: Dynamic, field: String = null, index: Int = -1): DynamicAccesor {
        this.obj = obj;
        this.field = field;
        this.index = index;
        return this;
    }

    /**
     * Returns `true` if this accesor is able to fetch a value at the moment.
     * The accesor needs to have enough information to be able to target a field.
     */
    public function isReady():Bool {
        return obj != null && (index >= 0 || (field != null && field.length > 0));
    }

    /**
     * Returns the value currently present in the field this accesor is
     * targeting at the moment.
     */
    public function getValue(): Dynamic {
        if (obj == null) {
            return null;
        } else if (index >= 0) {
            if (obj is FlxTypedGroup) {
                return obj.members[index];
            } else {
                return obj[index];
            }
        } else if (field == null || field.length == 0) {
            return obj;
        }
        var value:Dynamic = null;
        if (obj is MusicBeatState && obj.hasLuaObject(field)) {
            value = obj.getLuaObject(field);
        } else if (obj is PlayState && obj.variables.exists(field)) {
            value = obj.variables.get(field);
        } else if (obj is StringMap || obj is ObjectMap || obj is IntMap || obj is EnumValueMap) {
            value = obj.get(field);
        } else {
            value = Reflect.getProperty(obj, field);
        }
        if (value != null && value is ModchartTween)
            value = value.unwrap();
        return value;
    }

    /**
     * Sets a new value into the field this accesor is targeting at the moment.
     */
    public function setValue(value: Dynamic): Bool {
        if (obj == null) {
            return false;
        } else if (index >= 0) {
            if (obj is FlxTypedGroup) {
                obj.members[index] = value;
            } else {
                obj[index] = value;
            }
            return true;
        } else if (field == null || field.length == 0) {
            return false;
        }
        try {
            if (obj is PlayState && obj.variables.exists(field)) {
                obj.variables.set(field, value);
            } else if (obj is StringMap || obj is ObjectMap || obj is IntMap || obj is EnumValueMap) {
                obj.set(field, value);
            } else {
                Reflect.setProperty(obj, field, value);
            }
            return true;
        } catch (ex) {
            return false;
        }
    }
}