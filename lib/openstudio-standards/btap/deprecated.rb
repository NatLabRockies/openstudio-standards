# BTAP Deprecated
#
# 2026-07-09
# This file will house methods that aren't used inside OpenStudio Standards.
# NRCan task 486 involves cleaning up unused code, however since OpenStudio
# Standards is a library, other people could be using these methods despite them
# not being used inside this repository. For now, they are marked as deprecated
# unless someone expresses otherwise. If there are no concerns these methods
# will soon be removed for the purpose of making developer operations simpler.

module BTAP
  module Deprecated
    def self.msg(klass, method_name)
      warn("[BTAP::Deprecated] Warning to users of BTAP:" \
           "#{klass}##{method_name} is considered for deletion for the future" \
           "as of July 2026. If you are still using this method, please" \
           "contact nicholas.pneumaticos@nrcan-rncan.gc.ca.")
    end
  end

  deprecate_methods = proc do |target_klass, display_klass, methods_list|
    methods_list.each do |method_name|
      old_method = target_klass.instance_method(method_name)
      target_klass.class_eval do
        define_method(method_name) do |*args, &block|
          Deprecated.msg(display_klass, method_name)
          old_method.bind_call(self, *args, &block)
        end
      end
    end
  end

  constants.select { |c| const_get(c).is_a?(Class) }.each do |name|
    klass = const_get(name)
    deprecate_methods.call(klass, klass, klass.instance_methods(false))
    deprecate_methods.call(klass.singleton_class, klass, klass.methods(false))
  end
end
