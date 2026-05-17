shared_utils = import_module("../../shared_utils/shared_utils.star")
constants = import_module("../../package_io/constants.star")
static_files = import_module("../../static_files/static_files.star")
lighthouse = import_module("../../cl/lighthouse/lighthouse_launcher.star")
prysm = import_module("../../cl/prysm/prysm_launcher.star")

MEV_BUILDER_CONFIG_FILENAME = "config.toml"
MEV_BUILDER_MOUNT_DIRPATH_ON_SERVICE = "/config/"
MEV_BUILDER_FILES_ARTIFACT_NAME = "mev-rbuilder-epbs-config"
MEV_FILE_PATH_ON_CONTAINER = (
    MEV_BUILDER_MOUNT_DIRPATH_ON_SERVICE + MEV_BUILDER_CONFIG_FILENAME
)

EPBS_SERVER_PORT = 18551

CL_HTTP_PORTS = {
    "lighthouse": lighthouse.BEACON_HTTP_PORT_NUM,
    "prysm": prysm.BEACON_HTTP_PORT_NUM,
    "teku": 4000,
    "nimbus": 4000,
    "lodestar": 4000,
    "grandine": 4000,
}


def new_builder_config(
    plan,
    network_params,
    rbuilder_params,
    participants,
    global_node_selectors,
    builder_bls_secret_key=None,
    coinbase_secret_key=None,
):
    num_of_participants = shared_utils.zfill_custom(
        len(participants), len(str(len(participants)))
    )

    # Use builder BLS key if derived, otherwise fall back to default MEV secret key
    builder_secret_key = constants.DEFAULT_MEV_SECRET_KEY[2:]
    if builder_bls_secret_key != None:
        builder_secret_key = builder_bls_secret_key

    # Use the provided prefunded ECDSA key as the coinbase (payout tx signer);
    # fall back to the well-known DEFAULT_MEV_SECRET_KEY only if none was passed.
    coinbase_key = constants.DEFAULT_MEV_SECRET_KEY[2:]
    if coinbase_secret_key != None:
        coinbase_key = coinbase_secret_key
        if coinbase_key.startswith("0x"):
            coinbase_key = coinbase_key[2:]

    builder_template_data = new_builder_config_template_data(
        network_params,
        coinbase_key,
        builder_secret_key,
        num_of_participants,
        rbuilder_params,
    )

    rbuilder_config_template = read_file(
        static_files.RBUILDER_EPBS_CONFIG_FILEPATH
    )

    template_and_data = shared_utils.new_template_and_data(
        rbuilder_config_template, builder_template_data
    )

    template_and_data_by_rel_dest_filepath = {}
    template_and_data_by_rel_dest_filepath[
        MEV_BUILDER_CONFIG_FILENAME
    ] = template_and_data

    config_files_artifact_name = plan.render_templates(
        template_and_data_by_rel_dest_filepath, MEV_BUILDER_FILES_ARTIFACT_NAME
    )

    return config_files_artifact_name


def get_cl_http_port(cl_type):
    return CL_HTTP_PORTS.get(cl_type, lighthouse.BEACON_HTTP_PORT_NUM)


def new_builder_config_template_data(
    network_params,
    coinbase_secret_key,
    builder_secret_key,
    num_of_participants,
    rbuilder_params,
):
    cl_type = rbuilder_params.cl_type
    cl_http_port = get_cl_http_port(cl_type)

    # Use explicit cl_endpoint if provided, otherwise default to rbuilder's own CL
    if rbuilder_params.cl_endpoint:
        cl_endpoint = rbuilder_params.cl_endpoint
    else:
        cl_endpoint = "http://cl-{0}-{1}-{2}:{3}".format(
            num_of_participants,
            cl_type,
            constants.EL_TYPE.reth_builder,
            cl_http_port,
        )

    return {
        "Network": network_params.network
        if network_params.network in constants.PUBLIC_NETWORKS
        else "/network-configs/genesis.json",
        "DataDir": "/data/reth/execution-data",
        "CLEndpoint": cl_endpoint,
        "GenesisForkVersion": constants.GENESIS_FORK_VERSION,
        "CoinbaseSecretKey": coinbase_secret_key,
        "BuilderSecretKey": builder_secret_key,
        "EpbsEnabled": "true" if rbuilder_params.epbs_enabled else "false",
        "EpbsServerPort": rbuilder_params.epbs_server_port,
        "EpbsP2pEnabled": "true" if rbuilder_params.epbs_p2p_enabled else "false",
        "EpbsP2pBidStartMs": rbuilder_params.epbs_p2p_bid_start_ms,
        "EpbsP2pBidEndMs": rbuilder_params.epbs_p2p_bid_end_ms,
        "EpbsP2pBidIntervalMs": rbuilder_params.epbs_p2p_bid_interval_ms,
        "EpbsP2pBidValueIncrementGwei": rbuilder_params.epbs_p2p_bid_value_increment_gwei,
        "EpbsP2pBidValueSubsidyGwei": rbuilder_params.epbs_p2p_bid_value_subsidy_gwei,
    }
