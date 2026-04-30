import { Module } from '@nestjs/common';
import { DeliveryAgentsController } from './delivery-agents.controller';
import { DeliveryAgentsService } from './delivery-agents.service';

@Module({
  controllers: [DeliveryAgentsController],
  providers: [DeliveryAgentsService]
})
export class DeliveryAgentsModule {}
