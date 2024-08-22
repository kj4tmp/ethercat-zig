//! Subdevice Information Interface (SII)
//!
//! Address is word (two-byte) address.

// TODO: refactor for less repetition

const nic = @import("nic.zig");
const Port = nic.Port;
const eCatFromPack = nic.eCatFromPack;
const packFromECat = nic.packFromECat;

const std = @import("std");
const Timer = std.time.Timer;
const ns_per_us = std.time.ns_per_us;
const esc = @import("esc.zig");
const commands = @import("commands.zig");

pub const ParameterMap = enum(u16) {
    PDI_control = 0x0000,
    PDI_configuration = 0x0001,
    sync_impulse_length_10ns = 0x0002,
    PDI_configuration2 = 0x0003,
    configured_station_alias = 0x0004,
    // reserved = 0x0005,
    checksum_0_to_6 = 0x0007,
    vendor_id = 0x0008,
    product_code = 0x000A,
    revision_number = 0x000C,
    serial_number = 0x000E,
    // reserved = 0x00010,
    bootstrap_recv_mbx_offset = 0x0014,
    bootstrap_recv_mbx_size = 0x0015,
    bootstrap_send_mbx_offset = 0x0016,
    bootstrap_send_mbx_size = 0x0017,
    std_recv_mbx_offset = 0x0018,
    std_recv_mbx_size = 0x0019,
    std_send_mbx_offset = 0x001A,
    std_send_mbx_size = 0x001B,
    mbx_protocol = 0x001C,
    // reserved = 0x001D,
    size = 0x003E,
    version = 0x003F,
    first_catagory_header = 0x0040,
};

/// Supported Mailbox Protocols
///
/// Ref: IEC 61158-6-12:2019 5.4 Table 18
pub const MailboxProtocolSupported = packed struct(u16) {
    AoE: bool,
    EoE: bool,
    CoE: bool,
    FoE: bool,
    SoE: bool,
    VoE: bool,
    reserved: u10 = 0,
};

pub const SubdeviceInfo = packed struct {
    PDI_control: u16,
    PDI_configuration: u16,
    sync_inpulse_length_10ns: u16,
    PDI_configuation2: u16,
    configured_station_alias: u16,
    reserved: u32 = 0,
    checksum: u16,
    vendor_id: u32,
    product_code: u32,
    revision_number: u32,
    serial_number: u32,
    reserved2: u64 = 0,
    bootstrap_recv_mbx_offset: u16,
    bootstrap_recv_mbx_size: u16,
    bootstrap_send_mbx_offset: u16,
    bootstrap_send_mbx_size: u16,
    std_recv_mbx_offset: u16,
    std_recv_mbx_size: u16,
    std_send_mbx_offset: u16,
    std_send_mbx_size: u16,
    mbx_protocol: MailboxProtocolSupported,
    reserved3: u528 = 0,
    /// size of EEPROM in kbit + 1, kbit = 1024 bits, 0 = 1 kbit.
    size: u16,
    version: u16,
};

pub const SubdeviceIdentity = packed struct {
    vendor_id: u32,
    product_code: u32,
    revision_number: u32,
};

/// SII Catagory Types
///
/// Ref: IEC 61158-6-12:2019 5.4 Table 19
pub const CatagoryType = enum(u15) {
    NOP = 0,
    strings = 10,
    data_types = 20,
    general = 30,
    FMMU = 40,
    sync_manager = 41,
    TXPDO = 50,
    RXPDO = 51,
    DC = 60,
    // end of SII is 0xffffffffffff...
    end_of_file = 0b111_1111_1111_1111,
    _,
};

pub const CatagoryHeader = packed struct {
    catagory_type: CatagoryType,
    vendor_specific: u1,
    word_size: u16,
};

/// SII Catagory String
///
/// Ref: IEC 61158-6-12:2019 5.4 Table 20
pub const CatagoryString = packed struct {
    n_strings: u8,
    // after this there is alternating
    // str_len: u8
    // str: [str_len]u8
    // it is of type VISIBLESTRING
    // TODO: unsure if null-terminated and encoding
    // string index of 0 is empty string
    // first string has index 1
};

/// CoE Details
///
/// Ref: IEC 61158-6-12:2019 5.4 Table 21
pub const CoEDetails = packed struct(u8) {
    enable_SDO: bool,
    enable_SDO_info: bool,
    enable_PDO_assign: bool,
    enable_PDO_configuration: bool,
    enable_upload_at_startup: bool,
    enable_SDO_complete_access: bool,
    reserved: u2 = 0,
};

/// FoE Details
///
/// Ref: IEC 61158-6-12:2019 5.4 Table 21
pub const FoEDetails = packed struct(u8) {
    enable_foe: bool,
    reserved: u7 = 0,
};

/// EoE Details
///
/// Ref: IEC 61158-6-12:2019 5.4 Table 21
pub const EoEDetails = packed struct(u8) {
    enable_eoe: bool,
    reserved: u7 = 0,
};

/// Flags
///
/// Ref: IEC 61158-6-12:2019 5.4 Table 21
pub const Flags = packed struct(u8) {
    enable_SAFEOP: bool,
    enable_not_LRW: bool,
    mailbox_data_link_layer: bool,
    /// ID selector mirrored in AL status code
    identity_AL_status_code: bool,
    /// ID selector value mirrored in memory address in parameter
    /// physical memory address
    identity_physical_memory: bool,
    reserved: u3 = 0,
};

/// SII Catagory General
///
/// Ref: IEC 61158-6-12:2019 5.4 Table 21
pub const CatagoryGeneral = packed struct {
    /// group information (vendor-specific), index to STRINGS
    group_idx: u8,
    /// image name (vendor specific), index to STRINGS
    image_idx: u8,
    /// order idx (vnedor specific), index to STRINGS
    order_idx: u8,
    /// device name information (vendor specific), index to STRINGS
    name_idx: u8,
    reserved: u8 = 0,
    coe_details: CoEDetails,
    foe_details: FoEDetails,
    eoe_details: EoEDetails,
    /// reserved
    soe_details: u8 = 0,
    /// reserved
    ds402_channels: u8 = 0,
    /// reserved
    sysman_class: u8 = 0,
    flags: Flags,
    /// if flags.identity_physical_memory, this contains the ESC memory
    /// address where the ID switch is mirrored.
    physical_memory_address: u16,
};

/// FMMU information from the SII
///
/// Ref: IEC 61158-6-12:2019 5.4 Table 23
pub const FMMU = enum(u8) {
    not_used = 0x00,
    used_for_outputs = 0x01,
    used_for_inputs = 0x02,
    used_for_syncm_status = 0x03,
    not_used2 = 0xff,
    _,
};

/// Catagory FMMU
///
/// Contains a minimum of 2 FMMUs.
///
/// Ref: IEC 61158-6-12:2019 5.4 Table 23
pub const CatagoryFMMU = packed struct(u16) {
    FMMU0: FMMU,
    FMMU1: FMMU,
};

pub const EnableSyncMangager = packed struct(u8) {
    enable: bool,
    /// info for config tool, this syncM has fixed content
    fixed_content: bool,
    /// true when no hardware resource used
    virtual: bool,
    /// syncM should only be enabled in OP state
    OP_only: bool,
    reserved: u4 = 0,
};

pub const SyncMType = enum(u8) {
    not_used_or_unknown = 0x00,
    mailbox_out = 0x01,
    mailbox_in = 0x02,
    process_data_outputs = 0x03,
    process_data_inputs = 0x04,
    _,
};

/// SyncM Element
///
/// Ref: IEC 61158-6-12:2019 5.4 Table 24
pub const SyncM = packed struct {
    physical_start_address: u16,
    length: u16,
    /// defined mode of operation, see control register of sync manager
    control_register: u8,
    status_register: u8,
    enable_sync_manager: EnableSyncMangager,
    syncM_type: SyncMType,
};

/// PDO Entry
///
/// Ref: IEC 61158-6-12:2019 5.4 Table 26
pub const PDOEntry = packed struct {
    /// index of the entry
    index: u16,
    subindex: u8,
    /// name of the entry, index to STRINGS
    name_idx: u8,
    /// data type of the entry, index in CoE object dictionary
    data_type: u8,
    /// bit length of the entry
    bit_len: u8,
    /// reserved
    flags: u16 = 0,
};

/// Catagory PDO
///
/// Applies to both TXPDO and RXPDO SII catagories.
///
/// Ref: IEC 61158-6-12:2019 5.4 Table 25
pub const CatagoryPDO = packed struct {
    /// for RxPDO: 0x1600 to 0x17ff
    /// for TxPDO: 0x1A00 to 0x1bff
    index: u16,
    n_entries: u8,
    /// reference to sync manager
    syncM: u8,
    /// referece to DC synch
    synchronization: u8,
    /// name of object, index to STRINGS
    name_idx: u8,
    /// reserved
    flags: u16 = 0,
    // entries sequentially after this
};

pub const FindCatagoryResult = struct {
    /// word address of the data portion (not including header)
    word_address: u16,
    /// length of the data portion in bytes
    byte_length: u17,
};

/// find the word address of a catagory in the eeprom, uses station addressing.
pub fn findCatagoryFP(port: *Port, station_address: u16, catagory: CatagoryType, retries: u32, recv_timeout_us: u32, eeprom_timeout_us: u32) !FindCatagoryResult {

    // there shouldn't be more than 1000 catagories..right??
    var word_address: u16 = @intFromEnum(ParameterMap.first_catagory_header);
    for (0..1000) |_| {
        const catagory_header = try readSIIFP_ps(
            port,
            CatagoryHeader,
            station_address,
            word_address,
            retries,
            recv_timeout_us,
            eeprom_timeout_us,
        );
        std.log.info("station_address: 0x{x}, got catagory header: {}", .{ station_address, catagory_header });

        if (catagory_header.catagory_type == catagory) {
            std.log.info("found catagory: {}", .{catagory_header});
            // + 2 for catagory header, byte length = 2 * word length
            return .{ .word_address = word_address + 2, .byte_length = word_address << 1 };
        } else if (catagory_header.catagory_type == .end_of_file) {
            return error.NotFound;
        } else {
            word_address += catagory_header.word_size + 2; // + 2 for catagory header
            continue;
        }
        unreachable;
    } else {
        std.log.err("SII catagory {} not found.", .{catagory});
        return error.NotFound;
    }
}

/// read a packed struct from SII, using autoincrement addressing
pub fn readSIIAP_ps(
    port: *Port,
    comptime T: type,
    autoinc_address: u16,
    eeprom_address: u16,
    retries: u32,
    recv_timeout_us: u32,
    eeprom_timeout_us: u32,
) !T {
    const n_4_bytes = @divExact(@bitSizeOf(T), 32);
    var bytes: [@divExact(@bitSizeOf(T), 8)]u8 = undefined;

    for (0..n_4_bytes) |i| {
        const source = try readSII4ByteAP(
            port,
            autoinc_address,
            eeprom_address + 2 * @as(u16, @intCast(i)), // eeprom address is WORD address
            retries,
            recv_timeout_us,
            eeprom_timeout_us,
        );
        @memcpy(bytes[i * 4 .. i * 4 + 4], &source);
    }

    return nic.packFromECat(T, bytes);
}

/// read 4 bytes from SII, using autoincrement addressing
pub fn readSII4ByteAP(
    port: *Port,
    autoinc_address: u16,
    eeprom_address: u16,
    retries: u32,
    recv_timeout_us: u32,
    eeprom_timeout_us: u32,
) ![4]u8 {

    // set eeprom access to main device
    for (0..retries) |_| {
        const wkc = try commands.APWR_ps(
            port,
            esc.SIIAccessRegisterCompact{
                .owner = .ethercat_DL,
                .lock = false,
            },
            .{
                .autoinc_address = autoinc_address,
                .offset = @intFromEnum(esc.RegisterMap.SII_access),
            },
            recv_timeout_us,
        );
        if (wkc == 1) {
            break;
        }
    } else {
        return error.SubdeviceUnresponsive;
    }

    // ensure there is a rising edge in the read command by first sending zeros
    for (0..retries) |_| {
        var data = nic.zerosFromPack(esc.SIIControlStatusRegister);
        const wkc = try commands.APWR(
            port,
            .{
                .autoinc_address = autoinc_address,
                .offset = @intFromEnum(esc.RegisterMap.SII_control_status),
            },
            &data,
            recv_timeout_us,
        );
        if (wkc == 1) {
            break;
        }
    } else {
        return error.SubdeviceUnresponsive;
    }

    // send read command
    for (0..retries) |_| {
        const wkc = try commands.APWR_ps(
            port,
            esc.SIIControlStatusAddressRegister{
                .write_access = false,
                .EEPROM_emulation = false,
                .read_size = .four_bytes,
                .address_algorithm = .one_byte_address,
                .read_operation = true, // <-- cmd
                .write_operation = false,
                .reload_operation = false,
                .checksum_error = false,
                .device_info_error = false,
                .command_error = false,
                .write_error = false,
                .busy = false,
                .sii_address = eeprom_address,
            },
            .{
                .autoinc_address = autoinc_address,
                .offset = @intFromEnum(esc.RegisterMap.SII_control_status),
            },
            recv_timeout_us,
        );
        if (wkc == 1) {
            break;
        }
    } else {
        return error.SubdeviceUnresponsive;
    }

    var timer = try Timer.start();
    // wait for eeprom to be not busy
    while (timer.read() < eeprom_timeout_us * ns_per_us) {
        const sii_status = try commands.APRD_ps(
            port,
            esc.SIIControlStatusRegister,
            .{
                .autoinc_address = autoinc_address,
                .offset = @intFromEnum(
                    esc.RegisterMap.SII_control_status,
                ),
            },
            recv_timeout_us,
        );

        if (sii_status.wkc != 1) {
            continue;
        }
        if (sii_status.ps.busy) {
            continue;
        } else {
            // check for eeprom nack
            if (sii_status.ps.command_error) {
                return error.eepromCommandError;
            }
            break;
        }
    } else {
        return error.eepromTimeout;
    }

    // attempt read 3 times
    for (0..retries) |_| {
        var data = [4]u8{ 0, 0, 0, 0 };
        const wkc = try commands.APRD(
            port,
            .{
                .autoinc_address = autoinc_address,
                .offset = @intFromEnum(
                    esc.RegisterMap.SII_data,
                ),
            },
            &data,
            recv_timeout_us,
        );
        if (wkc == 1) {
            return data;
        }
    } else {
        return error.SubdeviceUnresponsive;
    }
}

/// read a packed struct from SII, using station addressing
pub fn readSIIFP_ps(
    port: *Port,
    comptime T: type,
    station_address: u16,
    eeprom_address: u16,
    retries: u32,
    recv_timeout_us: u32,
    eeprom_timeout_us: u32,
) !T {
    const n_4_bytes = @divExact(@bitSizeOf(T), 32);
    var bytes: [@divExact(@bitSizeOf(T), 8)]u8 = undefined;

    for (0..n_4_bytes) |i| {
        const source = try readSII4ByteFP(
            port,
            station_address,
            eeprom_address + 2 * @as(u16, @intCast(i)), // eeprom address is WORD address
            retries,
            recv_timeout_us,
            eeprom_timeout_us,
        );
        @memcpy(bytes[i * 4 .. i * 4 + 4], &source);
    }

    return nic.packFromECat(T, bytes);
}

/// read 4 bytes from SII, using station addressing
pub fn readSII4ByteFP(
    port: *Port,
    station_address: u16,
    eeprom_address: u16,
    retries: u32,
    recv_timeout_us: u32,
    eeprom_timeout_us: u32,
) ![4]u8 {

    // set eeprom access to main device
    for (0..retries) |_| {
        const wkc = try commands.FPWR_ps(
            port,
            esc.SIIAccessRegisterCompact{
                .owner = .ethercat_DL,
                .lock = false,
            },
            .{
                .station_address = station_address,
                .offset = @intFromEnum(esc.RegisterMap.SII_access),
            },
            recv_timeout_us,
        );
        if (wkc == 1) {
            break;
        }
    } else {
        return error.SubdeviceUnresponsive;
    }

    // ensure there is a rising edge in the read command by first sending zeros
    for (0..retries) |_| {
        var data = nic.zerosFromPack(esc.SIIControlStatusRegister);
        const wkc = try commands.FPWR(
            port,
            .{
                .station_address = station_address,
                .offset = @intFromEnum(esc.RegisterMap.SII_control_status),
            },
            &data,
            recv_timeout_us,
        );
        if (wkc == 1) {
            break;
        }
    } else {
        return error.SubdeviceUnresponsive;
    }

    // send read command
    for (0..retries) |_| {
        const wkc = try commands.FPWR_ps(
            port,
            esc.SIIControlStatusAddressRegister{
                .write_access = false,
                .EEPROM_emulation = false,
                .read_size = .four_bytes,
                .address_algorithm = .one_byte_address,
                .read_operation = true, // <-- cmd
                .write_operation = false,
                .reload_operation = false,
                .checksum_error = false,
                .device_info_error = false,
                .command_error = false,
                .write_error = false,
                .busy = false,
                .sii_address = eeprom_address,
            },
            .{
                .station_address = station_address,
                .offset = @intFromEnum(esc.RegisterMap.SII_control_status),
            },
            recv_timeout_us,
        );
        if (wkc == 1) {
            break;
        }
    } else {
        return error.SubdeviceUnresponsive;
    }

    var timer = try Timer.start();
    // wait for eeprom to be not busy
    while (timer.read() < eeprom_timeout_us * ns_per_us) {
        const sii_status = try commands.FPRD_ps(
            port,
            esc.SIIControlStatusRegister,
            .{
                .station_address = station_address,
                .offset = @intFromEnum(
                    esc.RegisterMap.SII_control_status,
                ),
            },
            recv_timeout_us,
        );

        if (sii_status.wkc != 1) {
            continue;
        }
        if (sii_status.ps.busy) {
            continue;
        } else {
            // check for eeprom nack
            if (sii_status.ps.command_error) {
                return error.eepromCommandError;
            }
            break;
        }
    } else {
        return error.eepromTimeout;
    }

    // attempt read 3 times
    for (0..retries) |_| {
        var data = [4]u8{ 0, 0, 0, 0 };
        const wkc = try commands.FPRD(
            port,
            .{
                .station_address = station_address,
                .offset = @intFromEnum(
                    esc.RegisterMap.SII_data,
                ),
            },
            &data,
            recv_timeout_us,
        );
        if (wkc == 1) {
            return data;
        }
    } else {
        return error.SubdeviceUnresponsive;
    }
}
