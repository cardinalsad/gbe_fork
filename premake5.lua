require("premake", ">=5.0.0-beta2")


-- add "-Wl,--whole-archive -Wl,-Bstatic -lmylib -Wl,-Bdynamic -Wl,--no-whole-archive"
-- via: links { 'mylib:static_whole' }
-- https://premake.github.io/docs/Overrides-and-Call-Arrays/#introducing-overrides
premake.override(premake.tools.gcc, "getlinks", function(originalFn, cfg, systemonly, nogroups)
    -- source:
    -- premake.tools.gcc.getlinks(cfg, systemonly, nogroups)
    -- https://github.com/premake/premake-core/blob/d842e671c7bc7e09f2eeaafd199fd01e48b87ee7/src/tools/gcc.lua#L568C15-L568C22

    local result = originalFn(cfg, systemonly, nogroups)
    local whole_syslibs = {"-Wl,--whole-archive"}
    local static_whole_syslibs = {"-Wl,--whole-archive -Wl,-Bstatic"}

    local endswith = function(s, ptrn)
        return ptrn == string.sub(s, -string.len(ptrn))
    end

    local idx_to_remove = {}
    for idx, name in ipairs(result) do
        if endswith(name, ":static_whole") then
            name = string.sub(name, 0, -14)
            table.insert(static_whole_syslibs, name) -- it already includes '-l'
            table.insert(idx_to_remove, idx)
        elseif endswith(name, ":whole_archive") then
            name = string.sub(name, 0, -15)
            table.insert(whole_syslibs, name) -- it already includes '-l'
            table.insert(idx_to_remove, idx)
        end
    end

    -- remove from the end to avoid trouble with table indexes shifting
    for iii = #idx_to_remove, 1, -1 do
        table.remove(result, idx_to_remove[iii])
    end

    local move = function(a1, a2)
        local t = #a2
        for i = 1, #a1 do a2[t + i] = a1[i] end
    end

    local new_result = {}
    if #whole_syslibs > 1 then
        table.insert(whole_syslibs, "-Wl,--no-whole-archive")
        move(whole_syslibs, new_result)
    end
    if #static_whole_syslibs > 1 then
        table.insert(static_whole_syslibs, "-Wl,-Bdynamic -Wl,--no-whole-archive")
        move(static_whole_syslibs, new_result)
    end

    -- https://stackoverflow.com/a/71719579
    -- because of the dumb way linux handles linking, the order becomes important
    -- I've encountered a problem with linking and it was failing with error "undefined reference to `__imp_WSACloseEvent'"
    -- despite 'Ws2_32' being added to the list of libraries, turns out some symbols from 'Ws2_32' were being stripped,
    -- because no library before it (on the command line) mentioned any of its symbols, the static libs were being appended afterwards on the command line,
    -- and they were mentioning some of the now-stripped symbols
    move(result, new_result)
    return new_result
end)


-- pre-define stuff

local os_iden = '' -- identifier
if os.target() == "windows" then
    os_iden = 'win'
elseif os.target() == "linux" then
    os_iden = 'linux'
else
    error('Unsupported os target: "' .. os.target() .. '"')
end

local deps_dir = path.getabsolute(path.join('build', 'deps', os_iden, _ACTION), _MAIN_SCRIPT_DIR)

function genproto()
    local deps_install_prefix = ''
    if os.is64bit() then
        deps_install_prefix = 'install64'
    else
        deps_install_prefix = 'install32'
    end
    local protoc_exe = path.join(deps_dir, 'protobuf', deps_install_prefix, 'bin', 'protoc')

    local out_dir = 'dll/proto_gen/' .. os_iden

    if os.host() == "windows" then
        protoc_exe = protoc_exe .. '.exe'
    end

    if not os.isfile(protoc_exe) then
        error("protoc not found! " .. protoc_exe)
        return
    end

    print("Generating from .proto file!")
    local ok_mk, err_mk = os.mkdir(out_dir)
    if not ok_mk then
        error("Error: " .. err_mk)
        return
    end
    
    if os.host() == "linux" then
        local ok_chmod, err_chmod = os.chmod(protoc_exe, "777")
        if not ok_chmod then
            error("Error: " .. err_chmod)
            return
        end
    end

    return os.execute(protoc_exe .. ' dll/net.proto -I./dll/ --cpp_out=' .. out_dir)
end

newoption {
    category = 'protobuf files',
    trigger = "genproto",
    description = "Generate .cc/.h files from .proto file",
}

newoption {
    category = 'build',
    trigger = "emubuild",
    description = "Set the EMU_BUILD_STRING",
    value = "your_string",
    default = os.date("%Y_%m_%d-%H_%M_%S"),
}

-- windows options
if os.target() == 'windows' then

newoption {
    category = "build",
    trigger = "dosstub",
    description = "Change the DOS stub of the Windows builds",
}

newoption {
    category = "build",
    trigger = "winsign",
    description = "Sign Windows builds with a fake certificate",
}

newoption {
    category = "build",
    trigger = "winrsrc",
    description = "Add resources to Windows builds",
}

end
-- End windows options


-- common defines
---------
local common_emu_defines = { -- added to all filters, later defines will be appended
    "UTF_CPP_CPLUSPLUS=201703L", "CURL_STATICLIB", "CONTROLLER_SUPPORT", "EMU_BUILD_STRING=" .. _OPTIONS["emubuild"],
}

-- include dirs
---------
local common_include = {
    'dll',
    'dll/proto_gen/' .. os_iden,
    'libs',
    'libs/utfcpp',
    'helpers',
    'crash_printer',
    'sdk',
    'controller',
    "overlay_experimental",
}

local x32_deps_include = {
    path.join(deps_dir, "libssq/include"),
    path.join(deps_dir, "curl/install32/include"),
    path.join(deps_dir, "protobuf/install32/include"),
    path.join(deps_dir, "zlib/install32/include"),
    path.join(deps_dir, "mbedtls/install32/include"),
}

local x32_deps_overlay_include = {
    path.join(deps_dir, "ingame_overlay/install32/include"),
    path.join(deps_dir, "ingame_overlay/deps/System/install32/include"),
    path.join(deps_dir, "ingame_overlay/deps/mini_detour/install32/include"),
}

local x64_deps_include = {
    path.join(deps_dir, "libssq/include"),
    path.join(deps_dir, "curl/install64/include"),
    path.join(deps_dir, "protobuf/install64/include"),
    path.join(deps_dir, "zlib/install64/include"),
    path.join(deps_dir, "mbedtls/install64/include"),
}

local x64_deps_overlay_include = {
    path.join(deps_dir, "ingame_overlay/install64/include"),
    path.join(deps_dir, "ingame_overlay/deps/System/install64/include"),
    path.join(deps_dir, "ingame_overlay/deps/mini_detour/install64/include"),
}


-- source & header files
---------
local common_files = {
    -- dll/
    "dll/*.cpp", "dll/*.c",
    "dll/*.hpp", "dll/*.h",
    -- dll/proto_gen/
    'dll/proto_gen/' .. os_iden .. '/*.cc', 'dll/proto_gen/' .. os_iden .. '/*.h',
    -- controller
    "controller/gamepad.c", "controller/controller/gamepad.h",
    -- crash_printer/
    'crash_printer/' .. os_iden .. '.cpp', 'crash_printer/crash_printer/' .. os_iden .. '.hpp',
    -- helpers/
    "helpers/common_helpers.cpp", "helpers/common_helpers/common_helpers.hpp",
}


-- libs to link
---------
local lib_prefix = 'lib'
local mingw_whole_archive = ''
-- MinGW on Windows adds this prefix by default and linking ex: '-lssq' will look for 'libssq'
-- so we have to ommit this prefix since it's automatically added
if _ACTION and string.match(_ACTION, 'gmake.*') then
    lib_prefix = ''
    mingw_whole_archive = ':whole_archive'
end
local common_link_win = {
    -- os specific
    "Ws2_32", "Iphlpapi", "Wldap32", "Winmm", "Bcrypt", "Dbghelp",
    -- gamepad
    "Xinput",
    -- imgui / overlay
    "Gdi32", "Dwmapi",
    -- deps
    "ssq" .. mingw_whole_archive,
    "zlibstatic" .. mingw_whole_archive,
    lib_prefix .. "curl" .. mingw_whole_archive,
    lib_prefix .. "protobuf-lite" .. mingw_whole_archive,
    "mbedcrypto" .. mingw_whole_archive,
}

local common_link_linux = {
    -- os specific
    "pthread", "dl",
    -- deps
    "ssq:static_whole",
    "z:static_whole", -- libz library
    "curl:static_whole",
    "protobuf-lite:static_whole",
    "mbedcrypto:static_whole",
}

-- overlay libs
local overlay_link_win = {
    "ingame_overlay" .. mingw_whole_archive,
    "system" .. mingw_whole_archive, -- ingame_overlay dependency
    "mini_detour" .. mingw_whole_archive, -- ingame_overlay dependency
}
local overlay_link_linux = {
    "ingame_overlay:static_whole",
    "system:static_whole", -- ingame_overlay dependency
    "mini_detour:static_whole", -- ingame_overlay dependency
}


-- dirs to custom libs
---------
local x32_ssq_libdir = path.join(deps_dir, "libssq/build32")
local x64_ssq_libdir = path.join(deps_dir, "libssq/build64")
if _ACTION and string.match(_ACTION, 'vs.+') then
    x32_ssq_libdir = x32_ssq_libdir .. "/Release"
    x64_ssq_libdir = x64_ssq_libdir .. "/Release"
end

local x32_deps_libdir = {
    x32_ssq_libdir,
    path.join(deps_dir, "curl/install32/lib"),
    path.join(deps_dir, "protobuf/install32/lib"),
    path.join(deps_dir, "zlib/install32/lib"),
    path.join(deps_dir, "mbedtls/install32/lib"),
}

local x32_deps_overlay_libdir = {
    path.join(deps_dir, "ingame_overlay/install32/lib"),
    path.join(deps_dir, "ingame_overlay/deps/System/install32/lib"),
    path.join(deps_dir, "ingame_overlay/deps/mini_detour/install32/lib"),
}

local x64_deps_libdir = {
    x64_ssq_libdir,
    path.join(deps_dir, "curl/install64/lib"),
    path.join(deps_dir, "protobuf/install64/lib"),
    path.join(deps_dir, "zlib/install64/lib"),
    path.join(deps_dir, "mbedtls/install64/lib"),
    path.join(deps_dir, "ingame_overlay/install64/lib"),
}

local x64_deps_overlay_libdir = {
    path.join(deps_dir, "ingame_overlay/install64/lib"),
    path.join(deps_dir, "ingame_overlay/deps/System/install64/lib"),
    path.join(deps_dir, "ingame_overlay/deps/mini_detour/install64/lib"),
}

-- generate proto
if _OPTIONS["genproto"] then
    if genproto() then
        print("Success!")
    else
        error("protoc error")
    end
end
-- End generate proto



-- tokenization
-- https://premake.github.io/docs/Tokens/
-- this means expand the global var 'abc' --> %{abc}
-- this means expand the global var 'abc' and resolve its full path --> %{!abc}
-- this means expand the global var 'abc' as a filepath agnostic to the shell (bash/cmd) --> %[%{abc}]

-- string concat and functions calls
-- https://premake.github.io/docs/Your-First-Script#functions-and-arguments
-- "asd" .. "zxc" --> "asdzxc"
-- when doing string concat, call premake functions/actions with regular brackets
-- this will work: targetdir("build/" .. os_iden)
-- this will fail: targetdir "build/" .. os_iden
-- both are function calls actually, ex: filter({ 'a', 'b' }) is similar to filter { 'a', 'b' }

-- stuff defined globally will affect all workspaces & projects
-- https://premake.github.io/docs/Scopes-and-Inheritance/

filter {} -- reset the filter and remove all active keywords
configurations { "debug", "release", }
platforms { "x64", "x32", }
language "C++"
cppdialect "C++17"
cdialect "C17"
filter { "system:linux", "action:gmake*" , }
    cdialect("gnu17") -- gamepad.c relies on some linux-specific functions like strdup() and MAX_PATH
filter {} -- reset the filter and remove all active keywords
characterset "Unicode"
staticruntime "on" -- /MT or /MTd
runtime "Release" -- ensure we never link with /MTd, otherwise deps linking will fail
flags {
    "NoPCH", -- no precompiled header on Windows
    "MultiProcessorCompile", -- Enable Visual Studio to use multiple compiler processes when building
    "RelativeLinks",
}
targetprefix "" -- prevent adding the prefix libxxx on linux
visibility "Hidden" -- hide all symbols by default on GCC (unless they are marked visible)
exceptionhandling "On" -- "Enable exception handling. ... although it does not affect execution."
vpaths { -- just for visual niceness, see: https://premake.github.io/docs/vpaths/
    ["headers/*"] = {
        "**.h", "**.hxx", "**.hpp",
    },
    ["src/*"] = {
        "**.c", "**.cxx", "**.cpp", "**.cc",
    },
    ["asm/*"] = {
        "**.s", "**.asm",
    },
}


-- arch
---------
filter { "platforms:x32", }
    architecture "x86" 
filter { "platforms:x64", }
    architecture "x86_64"


-- debug/optimization flags
---------
filter {} -- reset the filter and remove all active keywords
intrinsics "On"
filter { "configurations:*debug", }
    symbols "On"
    optimize "Off"
filter { "configurations:*release", }
    symbols "Off"
    optimize "On"


--- common compiler/linker options
---------
-- Visual Studio common compiler/linker options
filter { "action:vs*", }
    buildoptions  {
        "/permissive-", "/DYNAMICBASE",
        "/utf-8", "/Zc:char8_t-", "/EHsc", "/GL-"
    }
    linkoptions  {
        -- source of emittoolversioninfo: https://developercommunity.visualstudio.com/t/add-linker-option-to-strip-rich-stamp-from-exe-hea/740443
        "/NOLOGO", "/emittoolversioninfo:no"
    }
-- GNU make common compiler/linker options
filter { "action:gmake*", }
    buildoptions  {
        -- https://gcc.gnu.org/onlinedocs/gcc/Code-Gen-Options.html
        "-fno-jump-tables" , "-Wno-switch",
    }
    linkoptions {
        "-Wl,--exclude-libs,ALL",
    }
-- this is made separate because GCC complains but not CLANG
filter { "action:gmake*" , "files:*.cpp or *.cxx or *.cc or *.hpp", }
    buildoptions  {
        "-fno-char8_t", -- GCC gives a warning when a .c file is compiled with this
    }
filter {} -- reset the filter and remove all active keywords


-- defines
---------
-- release mode defines
filter { "configurations:*release" }
    defines {
        "NDEBUG", "EMU_RELEASE_BUILD"
    }
-- debug mode defines
filter { "configurations:*debug" }
    defines {
        "DEBUG",
    }
-- Windows defines
filter { "system:windows", }
    defines {
        "_CRT_SECURE_NO_WARNINGS",
    }
-- Linux defines
filter { "system:linux" }
    defines {
        "GNUC",
    }


-- MinGw on Windows
-- common compiler/linker options: source: https://gcc.gnu.org/onlinedocs/gcc/Cygwin-and-MinGW-Options.html
---------
filter { "system:windows", "action:gmake*", }
    -- MinGw on Windows common defines
    -- MinGw on Windows doesn't have a definition for '_S_IFDIR' which is microsoft specific: https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/stat-functions
    -- this is used in 'base.cpp' -> if ( buffer.st_mode & _S_IFDIR)
    -- instead microsoft has an alternative but only enabled when _CRT_DECLARE_NONSTDC_NAMES is defined
    -- https://learn.microsoft.com/en-us/cpp/c-runtime-library/compatibility
    defines {
        -- '_CRT_NONSTDC_NO_WARNINGS',
        '_CRT_DECLARE_NONSTDC_NAMES',
    }
    linkoptions {
        -- I don't know why but if libgcc/libstdc++ as well as pthreads are not statically linked
        -- none of the output binary .dlls will reach their DllMain() in x64dbg
        -- even when they're force-loaded in any process they immediately unload
        -- '-static-libgcc' ,'-static-libstdc++',
        '-static',
    }
-- MinGw on Windows cannot compile 'creatwth.cpp' from Detours lib (error: 'DWordMult' was not declared in this scope)
-- because intsafe.h isn't included by default
filter { "system:windows", "action:gmake*", "files:**/detours/creatwth.cpp" }
    buildoptions  {
        "-include intsafe.h",
    }



-- post build change DOS stub + sign
---------
if os.target() == "windows" then

-- token expansion like '%{cfg.platform}' happens later during project build
local dos_stub_exe = path.translate(path.getabsolute('resources/win/file_dos_stub/file_dos_stub_%{cfg.platform}.exe', _MAIN_SCRIPT_DIR), '\\')
local signer_tool = path.translate(path.getabsolute('third-party/build/win/cert/sign_helper.bat', _MAIN_SCRIPT_DIR), '\\')
-- change dos stub
filter { "system:windows", "options:dosstub", }
    postbuildcommands {
        '"' .. dos_stub_exe .. '" %[%{!cfg.buildtarget.abspath}]',
    }
-- sign
filter { "system:windows", "options:winsign", }
    postbuildcommands {
        '"' .. signer_tool .. '" %[%{!cfg.buildtarget.abspath}]',
    }
filter {} -- reset the filter and remove all active keywords

end


workspace "gbe"
    location("build/project/%{_ACTION}/" .. os_iden)



-- Project api_regular
---------
project "api_regular"
    kind "SharedLib"
    location "%{wks.location}/%{prj.name}"
    targetdir("build/" .. os_iden .. "/%{_ACTION}/%{cfg.buildcfg}/regular/%{cfg.platform}")


    -- name
    ---------
    filter { "system:windows", "platforms:x32", }
        targetname "steam_api"
    filter { "system:windows", "platforms:x64", }
        targetname "steam_api64"
    filter { "system:linux", }
        targetname "libsteam_api"


    -- defines
    ---------
    filter {} -- reset the filter and remove all active keywords
    defines { -- added to all filters, later defines will be appended
        common_emu_defines,
    }

    -- include dir
    ---------
    -- common include dir
    filter {} -- reset the filter and remove all active keywords
    includedirs {
        common_include,
    }

    -- x32 include dir
    filter { "platforms:x32", }
        includedirs {
            x32_deps_include,
        }

    -- x64 include dir
    filter { "platforms:x64", }
        includedirs {
            x64_deps_include,
        }


    -- common source & header files
    ---------
    filter {} -- reset the filter and remove all active keywords
    files { -- added to all filters, later defines will be appended
        common_files,
    }
    -- Windows common source files
    filter { "system:windows", }
        removefiles {
            "dll/wrap.cpp"
        }
    -- Windows x32 common source files
    filter { "system:windows", "platforms:x32", "options:winrsrc", }
        files {
            "resources/win/api/32/resources.rc"
        }
    -- Windows x64 common source files
    filter { "system:windows", "platforms:x64", "options:winrsrc", }
        files {
            "resources/win/api/64/resources.rc"
        }


    -- libs to link
    ---------
    -- Windows libs to link
    filter { "system:windows", }
        links {
            common_link_win,
        }

    -- Linux libs to link
    filter { "system:linux", }
        links {
            common_link_linux,
        }


    -- libs search dir
    ---------
    -- x32 libs search dir
    filter { "platforms:x32", }
        libdirs {
            x32_deps_libdir,
        }
    -- x64 libs search dir
    filter { "platforms:x64", }
        libdirs {
            x64_deps_libdir,
        }
-- End api_regular


-- Project api_experimental
---------
project "api_experimental"
    kind "SharedLib"
    location "%{wks.location}/%{prj.name}"
    targetdir("build/" .. os_iden .. "/%{_ACTION}/%{cfg.buildcfg}/experimental/%{cfg.platform}")


    -- name
    ---------
    filter { "system:windows", "platforms:x32", }
        targetname "steam_api"
    filter { "system:windows", "platforms:x64", }
        targetname "steam_api64"
    filter { "system:linux", }
        targetname "libsteam_api"


    -- defines
    ---------
    filter {} -- reset the filter and remove all active keywords
    defines { -- added to all filters, later defines will be appended
        common_emu_defines,
        "EMU_OVERLAY", "ImTextureID=ImU64",
    }
    -- Windows defines
    filter { "system:windows" }
        defines {
            "EMU_EXPERIMENTAL_BUILD",
        }


    -- include dir
    ---------
    -- common include dir
    filter {} -- reset the filter and remove all active keywords
    includedirs {
        common_include,
    }

    -- x32 include dir
    filter { "platforms:x32", }
        includedirs {
            x32_deps_include,
            x32_deps_overlay_include,
        }
    -- x64 include dir
    filter { "platforms:x64", }
        includedirs {
            x64_deps_include,
            x64_deps_overlay_include,
        }


    -- common source & header files
    ---------
    filter {} -- reset the filter and remove all active keywords
    files { -- added to all filters, later defines will be appended
        common_files,
        "overlay_experimental/**.cpp", "overlay_experimental/**.hpp",
        "overlay_experimental/**.c", "overlay_experimental/**.h",
    }
    -- Windows common source files
    filter { "system:windows", }
        files {
            "libs/detours/**.cpp", "libs/detours/**.hpp",
            "libs/detours/**.c", "libs/detours/**.h",
        }
        removefiles {
            "dll/wrap.cpp"
        }
    -- Windows x32 common source files
    filter { "system:windows", "platforms:x32", "options:winrsrc", }
        files {
            "resources/win/api/32/resources.rc"
        }
    -- Windows x64 common source files
    filter { "system:windows", "platforms:x64", "options:winrsrc", }
        files {
            "resources/win/api/64/resources.rc"
        }


    -- libs to link
    ---------
    -- Windows libs to link
    filter { "system:windows", }
        links {
            common_link_win,
            overlay_link_win,
        }

    -- Linux libs to link
    filter { "system:linux", }
        links {
            common_link_linux,
            overlay_link_linux,
        }


    -- libs search dir
    ---------
    -- x32 libs search dir
    filter { "platforms:x32", }
        libdirs {
            x32_deps_libdir,
            x32_deps_overlay_libdir,
        }
    -- x64 libs search dir
    filter { "platforms:x64", }
        libdirs {
            x64_deps_libdir,
            x64_deps_overlay_libdir,
        }
-- End api_experimental


-- Project steamclient_experimental
---------
project "steamclient_experimental"
    kind "SharedLib"
    location "%{wks.location}/%{prj.name}"
    
    -- targetdir
    ---------
    filter { "system:windows", }
        targetdir("build/" .. os_iden .. "/%{_ACTION}/%{cfg.buildcfg}/steamclient_experimental")
    filter { "system:linux", }
        targetdir("build/" .. os_iden .. "/%{_ACTION}/%{cfg.buildcfg}/experimental/%{cfg.platform}")


    -- name
    ---------
    filter { "system:windows", "platforms:x32", }
        targetname "steamclient"
    filter { "system:windows", "platforms:x64", }
        targetname "steamclient64"
    filter { "system:linux", }
        targetname "steamclient"
    

    -- defines
    ---------
    filter {} -- reset the filter and remove all active keywords
    defines { -- added to all filters, later defines will be appended
        common_emu_defines,
        "STEAMCLIENT_DLL", "EMU_OVERLAY", "ImTextureID=ImU64",
    }
    -- Windows defines
    filter { "system:windows" }
        defines {
            "EMU_EXPERIMENTAL_BUILD",
        }


    -- include dir
    ---------
    -- common include dir
    filter {} -- reset the filter and remove all active keywords
    includedirs {
        common_include,
    }

    -- x32 include dir
    filter { "platforms:x32", }
        includedirs {
            x32_deps_include,
            x32_deps_overlay_include,
        }

    -- x64 include dir
    filter { "platforms:x64", }
        includedirs {
            x64_deps_include,
            x64_deps_overlay_include,
        }


    -- common source & header files
    ---------
    filter {} -- reset the filter and remove all active keywords
    files { -- added to all filters, later defines will be appended
        common_files,
        "overlay_experimental/**.cpp", "overlay_experimental/**.hpp",
        "overlay_experimental/**.c", "overlay_experimental/**.h",
    }
    -- Windows common source files
    filter { "system:windows", }
        files {
            "libs/detours/**.cpp", "libs/detours/**.hpp",
            "libs/detours/**.c", "libs/detours/**.h",
        }
        removefiles {
            "dll/wrap.cpp"
        }
    -- Windows x32 common source files
    filter { "system:windows", "platforms:x32", "options:winrsrc", }
        files {
            "resources/win/client/32/resources.rc"
        }
    -- Windows x64 common source files
    filter { "system:windows", "platforms:x64", "options:winrsrc", }
        files {
            "resources/win/client/64/resources.rc"
        }


    -- libs to link
    ---------
    -- Windows libs to link
    filter { "system:windows", }
        links {
            common_link_win,
            overlay_link_win,
        }

    -- Linux libs to link
    filter { "system:linux", }
        links {
            common_link_linux,
            overlay_link_linux,
        }


    -- libs search dir
    ---------
    -- x32 libs search dir
    filter { "platforms:x32", }
        libdirs {
            x32_deps_libdir,
            x32_deps_overlay_libdir,
        }
    -- x64 libs search dir
    filter { "platforms:x64", }
        libdirs {
            x64_deps_libdir,
            x64_deps_overlay_libdir,
        }
-- End steamclient_experimental


-- Project tool_lobby_connect
---------
project "tool_lobby_connect"
    kind "ConsoleApp"
    location "%{wks.location}/%{prj.name}"
    targetdir("build/" .. os_iden .. "/%{_ACTION}/%{cfg.buildcfg}/tools/lobby_connect")
    targetname "lobby_connect_%{cfg.platform}"


    -- defines
    ---------
    filter {} -- reset the filter and remove all active keywords
    defines { -- added to all filters, later defines will be appended
        common_emu_defines,
        "NO_DISK_WRITES", "LOBBY_CONNECT",
    }
    removedefines {
        "CONTROLLER_SUPPORT",
    }


    -- include dir
    ---------
    -- common include dir
    filter {} -- reset the filter and remove all active keywords
    includedirs {
        common_include,
    }
    -- x32 include dir
    filter { "platforms:x32", }
        includedirs {
            x32_deps_include,
        }

    -- x64 include dir
    filter { "platforms:x64", }
        includedirs {
            x64_deps_include,
        }


    -- common source & header files
    ---------
    filter {} -- reset the filter and remove all active keywords
    files { -- added to all filters, later defines will be appended
        common_files,
        'tools/lobby_connect/lobby_connect.cpp'
    }
    removefiles {
        "controller/gamepad.c",
    }
    -- Windows x32 common source files
    filter { "system:windows", "platforms:x32", "options:winrsrc", }
        files {
            "resources/win/launcher/32/resources.rc"
        }
    -- Windows x64 common source files
    filter { "system:windows", "platforms:x64", "options:winrsrc", }
        files {
            "resources/win/launcher/64/resources.rc"
        }


    -- libs to link
    ---------
    -- Windows libs to link
    filter { "system:windows", }
        links {
            common_link_win,
            'Comdlg32',
        }

    -- Linux libs to link
    filter { "system:linux", }
        links {
            common_link_linux,
        }


    -- libs search dir
    ---------
    -- x32 libs search dir
    filter { "platforms:x32", }
        libdirs {
            x32_deps_libdir,
        }
    -- x64 libs search dir
    filter { "platforms:x64", }
        libdirs {
            x64_deps_libdir,
        }
-- End tool_lobby_connect


-- Project tool_generate_interfaces
project "tool_generate_interfaces"
    kind "ConsoleApp"
    location "%{wks.location}/%{prj.name}"
    targetdir("build/" .. os_iden .. "/%{_ACTION}/%{cfg.buildcfg}/tools/generate_interfaces")
    targetname "generate_interfaces_%{cfg.platform}"


    -- common source & header files
    ---------
    files {
        "tools/generate_interfaces/**"
    }
-- End tool_generate_interfaces


-- Project lib_steamnetworkingsockets START
project "lib_steamnetworkingsockets"
    kind "SharedLib"
    location "%{wks.location}/%{prj.name}"
    targetdir("build/" .. os_iden .. "/%{_ACTION}/%{cfg.buildcfg}/steamnetworkingsockets/%{cfg.platform}")
    targetname "steamnetworkingsockets"


    -- include dir
    ---------
    -- common include dir
    includedirs {
        common_include,
    }


    -- common source & header files
    ---------
    files {
        "networking_sockets_lib/**",
    }


-- End lib_steamnetworkingsockets


-- Project lib_game_overlay_renderer
project "lib_game_overlay_renderer"
    kind "SharedLib"
    location "%{wks.location}/%{prj.name}"


    -- targetdir
    ---------
    filter { "system:windows", }
        targetdir("build/" .. os_iden .. "/%{_ACTION}/%{cfg.buildcfg}/steamclient_experimental")
    filter { "system:linux", }
        targetdir("build/" .. os_iden .. "/%{_ACTION}/%{cfg.buildcfg}/gameoverlayrenderer/%{cfg.platform}")


    -- name
    ---------
    filter { "system:windows", "platforms:x32", }
        targetname "GameOverlayRenderer"
    filter { "system:windows", "platforms:x64", }
        targetname "GameOverlayRenderer64"
    filter { "system:linux", }
        targetname "gameoverlayrenderer"

    
    -- include dir
    ---------
    -- common include dir
    filter {} -- reset the filter and remove all active keywords
    includedirs {
        common_include,
    }
    -- x32 include dir
    filter { "platforms:x32", }
        includedirs {
            x32_deps_include,
        }

    -- x64 include dir
    filter { "platforms:x64", }
        includedirs {
            x64_deps_include,
        }


    -- common source & header files
    ---------
    filter {} -- reset the filter and remove all active keywords
    files {
        "game_overlay_renderer_lib/**"
    }
    -- x32 common source files
    filter { "system:windows", "platforms:x32", "options:winrsrc", }
        files {
            "resources/win/game_overlay_renderer/32/resources.rc"
        }
    -- x64 common source files
    filter { "system:windows", "platforms:x64", "options:winrsrc", }
        files {
            "resources/win/game_overlay_renderer/64/resources.rc"
        }
-- End lib_game_overlay_renderer



-- WINDOWS ONLY TARGETS START
if os.target() == "windows" then


-- Project steamclient_experimental_stub
---------
project "steamclient_experimental_stub"
    -- https://stackoverflow.com/a/63228027
    kind "SharedLib"
    location "%{wks.location}/%{prj.name}"
    targetdir("build/" .. os_iden .. "/%{_ACTION}/%{cfg.buildcfg}/experimental/%{cfg.platform}")


    -- name
    ---------
    filter { "platforms:x32", }
        targetname "steamclient"
    filter { "platforms:x64", }
        targetname "steamclient64"


    -- common source & header files
    ---------
    filter {} -- reset the filter and remove all active keywords
    files { -- added to all filters, later defines will be appended
        "steamclient/steamclient.cpp",
    }
    -- x32 common source files
    filter { "platforms:x32", "options:winrsrc", }
        files {
            "resources/win/client/32/resources.rc"
        }
    -- x64 common source files
    filter { "platforms:x64", "options:winrsrc", }
        files {
            "resources/win/client/64/resources.rc"
        }
-- End steamclient_experimental_stub


-- Project steamclient_experimental_extra
project "steamclient_experimental_extra"
    kind "SharedLib"
    location "%{wks.location}/%{prj.name}"
    targetdir("build/" .. os_iden .. "/%{_ACTION}/%{cfg.buildcfg}/steamclient_experimental/extra_dlls")
    targetname "steamclient_extra_%{cfg.platform}"


    -- include dir
    ---------
    -- common include dir
    filter {} -- reset the filter and remove all active keywords
    includedirs {
        common_include,
        'tools/steamclient_loader/win/extra_protection',
    }
    -- x32 include dir
    filter { "platforms:x32", }
        includedirs {
            x32_deps_include,
        }
    -- x64 include dir
    filter { "platforms:x64", }
        includedirs {
            x64_deps_include,
        }


    -- common source & header files
    ---------
    filter {} -- reset the filter and remove all active keywords
    files {
        "tools/steamclient_loader/win/extra_protection/**",
        "helpers/pe_helpers.cpp",
        "helpers/common_helpers.cpp",
        -- detours
        "libs/detours/**.cpp", "libs/detours/**.hpp",
        "libs/detours/**.c", "libs/detours/**.h",
    }
    -- x32 common source files
    filter { "platforms:x32", "options:winrsrc", }
        files {
            "resources/win/client/32/resources.rc"
        }
    -- x64 common source files
    filter { "platforms:x64", "options:winrsrc", }
        files {
            "resources/win/client/64/resources.rc"
        }
-- End steamclient_experimental_extra


-- Project steamclient_experimental_loader
project "steamclient_experimental_loader"
    kind "WindowedApp"
    location "%{wks.location}/%{prj.name}"
    targetdir("build/" .. os_iden .. "/%{_ACTION}/%{cfg.buildcfg}/steamclient_experimental")
    targetname "steamclient_loader_%{cfg.platform}"


    --- common compiler/linker options
    ---------
    -- MinGW on Windows
    filter { "action:gmake*", }
        -- source: https://gcc.gnu.org/onlinedocs/gcc/Cygwin-and-MinGW-Options.html
        linkoptions {
            -- MinGW on Windows cannot link wWinMain by default
            "-municode",
        }


    -- include dir
    ---------
    -- common include dir
    filter {} -- reset the filter and remove all active keywords
    includedirs {
        common_include,
    }
    -- x32 include dir
    filter { "platforms:x32", }
        includedirs {
            x32_deps_include,
        }
    -- x64 include dir
    filter { "platforms:x64", }
        includedirs {
            x64_deps_include,
        }


    -- common source & header files
    ---------
    filter {} -- reset the filter and remove all active keywords
    files {
        "tools/steamclient_loader/win/*.cpp",
        "helpers/pe_helpers.cpp",
        "helpers/common_helpers.cpp",
        "helpers/dbg_log.cpp",
    }
    -- x32 common source files
    filter { "platforms:x32", "options:winrsrc", }
        files {
            "resources/win/launcher/32/resources.rc"
        }
    -- x64 common source files
    filter { "platforms:x64", "options:winrsrc", }
        files {
            "resources/win/launcher/64/resources.rc"
        }


    -- libs to link
    ---------
    filter {} -- reset the filter and remove all active keywords
    links {
        -- common_link_win,
        'user32',
    }
-- End steamclient_experimental_loader


-- Project tool_file_dos_stub_changer
project "tool_file_dos_stub_changer"
    kind "ConsoleApp"
    location "%{wks.location}/%{prj.name}"
    targetdir("build/" .. os_iden .. "/%{_ACTION}/%{cfg.buildcfg}/file_dos_stub_changer")
    targetname "file_dos_stub_%{cfg.platform}"


    -- include dir
    ---------
    -- common include dir
    filter {} -- reset the filter and remove all active keywords
    includedirs {
        common_include,
    }


    -- common source & header files
    ---------
    filter {} -- reset the filter and remove all active keywords
    files {
        "resources/win/file_dos_stub/file_dos_stub.cpp",
        "helpers/pe_helpers.cpp",
        "helpers/common_helpers.cpp",
    }
-- End tool_file_dos_stub_changer

end
-- End WINDOWS ONLY TARGETS



-- LINUX ONLY TARGETS START
if os.target() == "linux" then

-- Project steamclient_regular
---------
project "steamclient_regular"
    kind "SharedLib"
    location "%{wks.location}/%{prj.name}"
    targetdir("build/" .. os_iden .. "/%{_ACTION}/%{cfg.buildcfg}/regular/%{cfg.platform}")
    targetname "steamclient"


    -- defines
    ---------
    filter {} -- reset the filter and remove all active keywords
    defines { -- added to all filters, later defines will be appended
        common_emu_defines,
        "STEAMCLIENT_DLL",
    }


    -- include dir
    ---------
    -- common include dir
    filter {} -- reset the filter and remove all active keywords
    includedirs {
        common_include,
    }
    -- x32 include dir
    filter { "platforms:x32", }
        includedirs {
            x32_deps_include,
        }
    -- x64 include dir
    filter { "platforms:x64", }
        includedirs {
            x64_deps_include,
        }


    -- common source & header files
    ---------
    filter {} -- reset the filter and remove all active keywords
    files { -- added to all filters, later defines will be appended
        common_files,
    }


    -- libs to link
    ---------
    filter {} -- reset the filter and remove all active keywords
    links { -- added to all filters, later defines will be appended
        common_link_linux,
    }

    -- libs search dir
    ---------
    -- x32 libs search dir
    filter { "platforms:x32", }
        libdirs {
            x32_deps_libdir,
        }
    -- x64 libs search dir
    filter { "platforms:x64", }
        libdirs {
            x64_deps_libdir,
        }
-- End steamclient_regular

end
-- End LINUX ONLY TARGETS

-- End Workspace
