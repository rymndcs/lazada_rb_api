# frozen_string_literal: true

# Conformance tests walk every adapter sample in one test, so they assert many times.
# rubocop:disable Minitest/MultipleAssertions

require_relative "helper"

module Conformance
  # The public surface equals the contract plus only the declared EXTENSIONS.
  class SurfaceTest < Minitest::Test
    include Support

    def extensions
      gem_module::EXTENSIONS.keys.map { |key| key.split("#", 2) }
    end

    def extension_members(class_name)
      extensions.select { |name, _| name == class_name }.map { |_, member| member.to_sym }
    end

    def contract_class_names
      CONTRACT[:classes].keys + CONTRACT[:data].keys + CONTRACT[:errors].keys
    end

    def extension_classes
      extensions.map(&:first).uniq - contract_class_names
    end

    # The contract's parameters, in order, plus only optional keywords declared in EXTENSIONS as "Class#keyword".
    # A declared keyword may sit anywhere among them (token_base_url: follows auth_base_url: by convention).
    def assert_initialize(class_name, params)
      actual = const(class_name).instance_method(:initialize).parameters
      extras = actual - params

      assert_equal params, actual - extras, "#{class_name}.new"
      extras.each do |kind, name|
        assert_equal :key, kind, "#{class_name}.new #{name}: an extra keyword must be optional"
        assert_includes extension_members(class_name), name, "#{class_name}.new #{name}: undeclared keyword"
      end
    end

    def test_contract_version
      assert_equal CONTRACT[:version], gem_module::CONTRACT_VERSION
      assert_match(/\A0\.\d+\.\d+\z/, gem_module::VERSION, "versions stay 0.x until the live recording round passes")
    end

    def test_extensions_are_a_frozen_hash_of_class_member_keys
      assert_predicate gem_module::EXTENSIONS, :frozen?
      gem_module::EXTENSIONS.each do |key, description|
        assert_match(/\A[A-Z]\w*(::[A-Z]\w*)*#\w+[?!]?\z/, key)
        assert_kind_of String, description
      end
    end

    def test_module_constants_are_exactly_the_contract_plus_extension_classes
      expected = CONTRACT[:module_constants] + extension_classes.map(&:to_sym)

      assert_equal expected.sort, gem_module.constants.sort
    end

    def test_endpoints_table_shape
      endpoints = gem_module::ENDPOINTS

      assert_predicate endpoints, :frozen?
      refute_empty endpoints
      endpoints.each do |name, hosts|
        assert_kind_of Symbol, name
        assert_equal token_host? ? %i[api auth token] : %i[api auth], hosts.keys.sort,
                     "#{name}: every entry carries :token exactly when Client#token_base_url is declared"
        hosts.each_value { |url| assert_match(%r{\Ahttps://[^/\s]+\S*\z}, url) }
      end
    end

    def test_class_constants
      CONTRACT[:class_constants].each do |class_name, names|
        names.each { |name| assert const(class_name).const_defined?(name, false), "#{class_name}::#{name} missing" }
      end

      assert_predicate gem_module::Shop::LOCATOR_KEYS, :frozen?
      CONTRACT[:batch_constants].each_value { |name| assert_kind_of Integer, gem_module::Products.const_get(name) }
    end

    def test_classes_define_exactly_the_contract_methods_with_exact_parameters
      CONTRACT[:classes].each do |class_name, spec|
        klass = const(class_name)
        expected = spec.fetch(:instance).keys + extension_members(class_name)

        assert_equal expected.sort, klass.public_instance_methods(false).sort, "#{class_name} public methods"
        spec[:instance].each do |name, params|
          assert_equal params, klass.instance_method(name).parameters, "#{class_name}##{name} parameters"
        end
        assert_initialize(class_name, spec[:initialize]) if spec.key?(:initialize)
        singleton = spec.fetch(:singleton, {})

        assert_equal singleton.keys.sort, klass.singleton_methods(false).sort, "#{class_name} singleton methods"
        singleton.each do |name, params|
          assert_equal params, klass.method(name).parameters, "#{class_name}.#{name} parameters"
        end
      end
    end

    def test_data_classes_have_exactly_the_contract_members
      CONTRACT[:data].each do |class_name, members|
        klass = const(class_name)

        assert_operator klass, :<, Data, "#{class_name} is a Data class"
        assert_equal (members + extension_members(class_name)).sort, klass.members.sort, "#{class_name} members"
        extra = klass.public_instance_methods(false) - klass.members - %i[inspect to_s]

        assert_empty extra, "#{class_name} has undeclared public methods"
      end
    end

    def test_extension_classes_expose_only_declared_methods
      extension_classes.each do |class_name|
        klass = const(class_name)

        assert_equal extension_members(class_name).sort, klass.public_instance_methods(false).sort, class_name
      end
    end

    def test_every_declared_extension_exists
      extensions.each do |class_name, member|
        klass = const(class_name)
        found = klass.public_method_defined?(member) || (klass < Data && klass.members.include?(member.to_sym))

        assert found, "declared extension #{class_name}##{member} does not exist"
      end
    end

    def test_error_tree
      CONTRACT[:errors].each do |name, parent|
        expected = parent == "StandardError" ? StandardError : const(parent)

        assert_equal expected, const(name).superclass, "#{name} < #{parent}"
      end
      CONTRACT[:api_error_methods].each do |method|
        assert gem_module::ApiError.public_method_defined?(method), "ApiError##{method}"
      end
      assert gem_module::TransportError.public_method_defined?(:retryable?)
    end
  end
end
# rubocop:enable Minitest/MultipleAssertions
