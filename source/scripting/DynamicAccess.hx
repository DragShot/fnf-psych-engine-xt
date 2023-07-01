package scripting;

using StringTools;

/**
 * Allows to access fields from the given object or class, these can be nested
 * inside other objects or in arrays.
 *
 * You can provide search paths as text, by following this template:
 * ```
 *     fieldName[index].fieldName[index]...
 * ```
 * Specifying indexes is optional. You can also stack more than one index
 * together (`field[idx][idx]`) if you want. Those will be resolved one at a
 * time.
 *
 * @author DragShot
 */
class DynamicAccess {

    /**
     * Returns an accesor for a field located with the given instance and path.
     * With it you can either get the current value of the field or set it.
     */
    public static function forField(instance: Dynamic, path: String): DynamicAccesor {
        if (instance == null || path == null) return null;
        return resolve(instance, path);
    }

    /**
     * Returns the value of a field located with the given instance and path.
     */
    public static function getField(instance: Dynamic, path: String): Dynamic {
        if (instance == null || path == null) return null;
        return resolve(instance, path).getValue();
    }

    /**
     * Sets the value of a field located with the given instance and path.
     */
    public static function setField(instance: Dynamic, path: String, value: Dynamic): Bool {
        if (instance == null || path == null) return false;
        return resolve(instance, path).setValue(value);
    }

    /**
     * Returns an accesor for a field located with the given class name and
     * path. With it you can either get the current value of the field or set
     * it.
     *
     * The first field in the path will be searched in the static space.
     */
    public static function forStatic(className: String, path: String): DynamicAccesor {
        if (className == null || path == null) return null;
        var class_ = Type.resolveClass(className);
        if (class_ == null) return null;
        return resolve(class_, path);
    }

    /**
     * Returns the value of a field located with the given class name and path.
     *
     * The first field in the path will be searched in the static space.
     */
    public static function getStatic(className: String, path: String): Dynamic {
        if (className == null || path == null) return null;
        var class_ = Type.resolveClass(className);
        if (class_ == null) return null;
        return resolve(class_, path).getValue();
    }

    /**
     * Sets the value of a field located with the given class name and path.
     *
     * The first field in the path will be searched in the static space.
     */
    public static function setStatic(className: String, path: String, value: Dynamic): Bool {
        if (className == null || path == null) return false;
        var class_ = Type.resolveClass(className);
        if (class_ == null) return false;
        return resolve(class_, path).setValue(value);
    }

    private static function resolve(value: Dynamic, path: String): DynamicAccesor {
        var accesor:DynamicAccesor = new DynamicAccesor();
        var paths:Array<String> = path.split('.');
        accesor.target(value);
        for (path in paths) {
            accesor = fetchField(accesor, path);
            if (!accesor.isReady()) break;
        }
        return accesor;
    }

    private static function fetchField(accesor: DynamicAccesor, path: String): DynamicAccesor {
        var splits = path.split('[');
        accesor.target(accesor.getValue(), splits[0]);
        if (splits.length > 1 && accesor.isReady()) {
            for (i in 1...splits.length) {
                var slot = Std.parseInt(splits[i].substring(0, splits[i].length-1));
                accesor.target(accesor.getValue(), null, slot);
                if (!accesor.isReady()) break;
            }
        }
        return accesor;
    }
}