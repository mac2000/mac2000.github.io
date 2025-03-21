$headers = @{ Authorization = "Bearer $env:OPENAI_API_KEY" }

$baseInstructions = @"
# System context

You are part of a multi-agent system called the Agents SDK, designed to make agent coordination and execution easy. 

Agents uses two primary abstraction: **Agents** and **Handoffs**.

An agent encompasses instructions and tools and can hand off a conversation to another agent when appropriate.

Handoffs are achieved by calling a handoff function, generally named `transfer_to_<agent_name>`.

Transfers between agents are handled seamlessly in the background; do not mention or draw attention to these transfers in your conversation with the user.
"@

$triageAgentInstructions = @"
$baseInstructions

You are a helpful triaging agent. You can use your tools to delegate questions to other appropriate agents.
"@

# note: tools here, are kind of fake functions to switch between available agents
$triageAgentTools = @(
  @{
    name        = "transfer_to_faq_agent"
    parameters  = @{
      additionalProperties = $false
      type                 = "object"
      properties           = @{}
      required             = @()
    }
    strict      = $true
    type        = "function"
    description = "Handoff to the FAQ Agent agent to handle the request. A helpful agent that can answer questions about the airline."
  }
  @{
    name        = "transfer_to_seat_booking_agent"
    parameters  = @{
      additionalProperties = $false
      type                 = "object"
      properties           = @{}
      required             = @()
    }
    strict      = $true
    type        = "function"
    description = "Handoff to the Seat Booking Agent agent to handle the request. A helpful agent that can update a seat on a flight."
  }
)

$seatBookingAgentInstructions = @"
$baseInstructions

You are a seat booking agent. If you are speaking to a customer, you probably were transferred to from the triage agent.

Use the following routine to support the customer.

# Routine

1. Ask for their confirmation number.
2. Ask the customer what their desired seat number is.
3. Use the update seat tool to update the seat on the flight.

If the customer asks a question that is not related to the routine, transfer back to the triage agent. """,
"@

$seatBookingAgentTools = @(
  # real function, that is supposed to update seat by calling external API
  @{
    name        = "update_seat"
    parameters  = @{
      properties           = @{
        confirmation_number = @{
          description = "The confirmation number for the flight."
          title       = "Confirmation Number"
          type        = "string"
        }
        new_seat            = @{
          description = "The new seat to update to."
          title       = "New Seat"
          type        = "string"
        }
      }
      required             = @("confirmation_number", "new_seat")
      title                = "update_seat_args"
      type                 = "object"
      additionalProperties = $false
    }
    strict      = $true
    type        = "function"
    description = "Update the seat for a given confirmation number."
  },
  # fake function, to switch back to triage agent
  @{
    name        = "transfer_to_triage_agent"
    parameters  = @{
      additionalProperties = $false
      type                 = "object"
      properties           = @{}
      required             = @()
    }
    strict      = $true
    type        = "function"
    description = "Handoff to the Triage Agent agent to handle the request. A triage agent that can delegate a customer's request to the appropriate agent."
  }
)

$faqAgentInstructions = @"
$baseInstructions

You are an FAQ agent. If you are speaking to a customer, you probably were transferred to from the triage agent.

Use the following routine to support the customer.

# Routine

1. Identify the last question asked by the customer.
2. Use the faq lookup tool to answer the question. Do not rely on your own knowledge.
3. If you cannot answer the question, transfer back to the triage agent.
"@

$faqAgentTools = @(
  # real function, that is supposed to update seat by calling external API
  @{
    name        = "faq_lookup_tool"
    parameters  = @{
      properties           = @{
        question = @{
          title = "Question"
          type  = "string"
        }
      }
      required             = @("question")
      title                = "faq_lookup_tool_args"
      type                 = "object"
      additionalProperties = $false
    }
    strict      = $true
    type        = "function"
    description = "Lookup frequently asked questions."
  },
  # fake function, to switch back to triage agent
  @{
    name        = "transfer_to_triage_agent"
    parameters  = @{
      additionalProperties = $false
      type                 = "object"
      properties           = @{}
      required             = @()
    }
    strict      = $true
    type        = "function"
    description = "Handoff to the Triage Agent agent to handle the request. A triage agent that can delegate a customer's request to the appropriate agent."
  }
)

# ---------------------------------
# Initiating conversation with: "lets book a seat" input

$res = Invoke-RestMethod -Method Post -Uri "https://api.openai.com/v1/responses" -Headers $headers -ContentType "application/json; charset=utf-8" -Body (ConvertTo-Json -Depth 100 -InputObject @{
    input        = @(
      @{
        role    = "user"
        content = "lets book a seat"
      }
    )
    model        = "gpt-4o"
    include      = @()
    instructions = $triageAgentInstructions
    stream       = $false
    tools        = $triageAgentTools
  })

$res.output | ConvertTo-Json -Depth 100
<#
{
  "type": "function_call",
  "id": "fc_67dd454a755c819285f15face0783c1b02e59d3f1f3c7ab8",
  "call_id": "call_VbNO0xX5vd4a6RfonLs1A0nw",
  "name": "transfer_to_seat_booking_agent",
  "arguments": "{}",
  "status": "completed"
}
#>
# note: model asks us to call our fake function that will switch to seat booking agent

# ---------------------------------
# in response, model asks us to call `transfer_to_seat_booking_agent` function
# which is fake one, so lets append messages to conversation
# as if we have switched agent

$res = Invoke-RestMethod -Method Post -Uri "https://api.openai.com/v1/responses" -Headers $headers -ContentType "application/json; charset=utf-8" -Body (ConvertTo-Json -Depth 100 -InputObject @{
    input        = @(
      @{
        role    = "user"
        content = "lets book a seat"
      },
      # append previous response as is
      @{
        type      = "function_call"
        id        = "fc_67dd454a755c819285f15face0783c1b02e59d3f1f3c7ab8"
        call_id   = "call_VbNO0xX5vd4a6RfonLs1A0nw"
        name      = "transfer_to_seat_booking_agent"
        arguments = "{}"
        status    = "completed"
      },
      # append fake function call result
      @{
        call_id = "call_VbNO0xX5vd4a6RfonLs1A0nw"
        output  = "{`"assistant`": `"Seat Booking Agent`"}"
        type    = "function_call_output"
      }
    )
    model        = "gpt-4o"
    include      = @()
    instructions = $seatBookingAgentInstructions
    stream       = $false
    tools        = $seatBookingAgentTools
  })

$res.output | ConvertTo-Json -Depth 100
<#
{
  "type": "message",
  "id": "msg_67dd482c2c3c8192a9adda691b9d113502e59d3f1f3c7ab8",
  "status": "completed",
  "role": "assistant",
  "content": [
    {
      "type": "output_text",
      "text": "Sure, I can help with that. Could you please provide your confirmation number?",
      "annotations": []
    }
  ]
}
#>

# note: here we are starting conversation with seat booking agent

# ---------------------------------
# in response, model asks us to ask for confirmation number
# lets append response to conversation

$res = Invoke-RestMethod -Method Post -Uri "https://api.openai.com/v1/responses" -Headers $headers -ContentType "application/json; charset=utf-8" -Body (ConvertTo-Json -Depth 100 -InputObject @{
    input        = @(
      @{
        role    = "user"
        content = "lets book a seat"
      },
      @{
        type      = "function_call"
        id        = "fc_67dd454a755c819285f15face0783c1b02e59d3f1f3c7ab8"
        call_id   = "call_VbNO0xX5vd4a6RfonLs1A0nw"
        name      = "transfer_to_seat_booking_agent"
        arguments = "{}"
        status    = "completed"
      },
      @{
        call_id = "call_VbNO0xX5vd4a6RfonLs1A0nw"
        output  = "{`"assistant`": `"Seat Booking Agent`"}"
        type    = "function_call_output"
      },
      # add previous response as is
      @{
        type    = "message"
        id      = "msg_67dd482c2c3c8192a9adda691b9d113502e59d3f1f3c7ab8"
        status  = "completed"
        role    = "assistant"
        content = @(
          @{
            type        = "output_text"
            text        = "Sure, I can help with that. Could you please provide your confirmation number?"
            annotations = @()
          }
        )
      },
      # and the user response
      @{
        role    = "user"
        content = "123"
      }
    )
    model        = "gpt-4o"
    include      = @()
    instructions = $seatBookingAgentInstructions
    stream       = $false
    tools        = $seatBookingAgentTools
  })

$res.output | ConvertTo-Json -Depth 100
<#
{
  "type": "message",
  "id": "msg_67dd490980dc8192ae78d48fb3db352302e59d3f1f3c7ab8",
  "status": "completed",
  "role": "assistant",
  "content": [
    {
      "type": "output_text",
      "text": "Thank you. What seat number would you like to update to?",
      "annotations": []
    }
  ]
}
#>

# note: to call `update_seat` function, we need to not only confirmation number, but also new seat number
# that's why models asks for second parameter

# ---------------------------------


$res = Invoke-RestMethod -Method Post -Uri "https://api.openai.com/v1/responses" -Headers $headers -ContentType "application/json; charset=utf-8" -Body (ConvertTo-Json -Depth 100 -InputObject @{
    input        = @(
      @{
        role    = "user"
        content = "lets book a seat"
      },
      @{
        type      = "function_call"
        id        = "fc_67dd454a755c819285f15face0783c1b02e59d3f1f3c7ab8"
        call_id   = "call_VbNO0xX5vd4a6RfonLs1A0nw"
        name      = "transfer_to_seat_booking_agent"
        arguments = "{}"
        status    = "completed"
      },
      @{
        call_id = "call_VbNO0xX5vd4a6RfonLs1A0nw"
        output  = "{`"assistant`": `"Seat Booking Agent`"}"
        type    = "function_call_output"
      },
      @{
        type    = "message"
        id      = "msg_67dd482c2c3c8192a9adda691b9d113502e59d3f1f3c7ab8"
        status  = "completed"
        role    = "assistant"
        content = @(
          @{
            type        = "output_text"
            text        = "Sure, I can help with that. Could you please provide your confirmation number?"
            annotations = @()
          }
        )
      },
      @{
        role    = "user"
        content = "123"
      },
      # append previous response as is
      @{
        type    = "message"
        id      = "msg_67dd490980dc8192ae78d48fb3db352302e59d3f1f3c7ab8"
        status  = "completed"
        role    = "assistant"
        content = @(
          @{
            type        = "output_text"
            text        = "Thank you. What seat number would you like to update to?"
            annotations = @()
          }
        )
      },
      # and the user response
      @{
        role    = "user"
        content = "2B"
      }
    )
    model        = "gpt-4o"
    include      = @()
    instructions = $seatBookingAgentInstructions
    stream       = $false
    tools        = $seatBookingAgentTools
  })

$res.output | ConvertTo-Json -Depth 100
<#
{
  "type": "function_call",
  "id": "fc_67dd4d8eb0948192b3c8e6f1abb7d8e502e59d3f1f3c7ab8",
  "call_id": "call_ObtbCAvAuzEuCPgIwpE2awUe",
  "name": "update_seat",
  "arguments": "{\"confirmation_number\":\"123\",\"new_seat\":\"2B\"}",
  "status": "completed"
}
#>

# note: model did get all required params for `update_seat` function, so it asks us to call it
# after calling the function, we make one more call, passing results


# ---------------------------------


$res = Invoke-RestMethod -Method Post -Uri "https://api.openai.com/v1/responses" -Headers $headers -ContentType "application/json; charset=utf-8" -Body (ConvertTo-Json -Depth 100 -InputObject @{
    input        = @(
      @{
        role    = "user"
        content = "lets book a seat"
      },
      @{
        type      = "function_call"
        id        = "fc_67dd454a755c819285f15face0783c1b02e59d3f1f3c7ab8"
        call_id   = "call_VbNO0xX5vd4a6RfonLs1A0nw"
        name      = "transfer_to_seat_booking_agent"
        arguments = "{}"
        status    = "completed"
      },
      @{
        call_id = "call_VbNO0xX5vd4a6RfonLs1A0nw"
        output  = "{`"assistant`": `"Seat Booking Agent`"}"
        type    = "function_call_output"
      },
      @{
        type    = "message"
        id      = "msg_67dd482c2c3c8192a9adda691b9d113502e59d3f1f3c7ab8"
        status  = "completed"
        role    = "assistant"
        content = @(
          @{
            type        = "output_text"
            text        = "Sure, I can help with that. Could you please provide your confirmation number?"
            annotations = @()
          }
        )
      },
      @{
        role    = "user"
        content = "123"
      },
      @{
        type    = "message"
        id      = "msg_67dd490980dc8192ae78d48fb3db352302e59d3f1f3c7ab8"
        status  = "completed"
        role    = "assistant"
        content = @(
          @{
            type        = "output_text"
            text        = "Thank you. What seat number would you like to update to?"
            annotations = @()
          }
        )
      },
      @{
        role    = "user"
        content = "2B"
      },
      # pass previous response as is
      @{
        type      = "function_call"
        id        = "fc_67dd4d8eb0948192b3c8e6f1abb7d8e502e59d3f1f3c7ab8"
        call_id   = "call_ObtbCAvAuzEuCPgIwpE2awUe"
        name      = "update_seat"
        arguments = "{`"confirmation_number`":`"123`",`"new_seat`":`"2B`"}"
        status    = "completed"
      },
      # pass function call output
      @{
        call_id = "call_ObtbCAvAuzEuCPgIwpE2awUe"
        output  = "Updated seat to 2B for confirmation number 123"
        type    = "function_call_output"
      }
    )
    model        = "gpt-4o"
    include      = @()
    instructions = $seatBookingAgentInstructions
    stream       = $false
    tools        = $seatBookingAgentTools
  })

$res.output | ConvertTo-Json -Depth 100
<#
{
  "type": "message",
  "id": "msg_67dd4e954c508192be7923a02976bbc302e59d3f1f3c7ab8",
  "status": "completed",
  "role": "assistant",
  "content": [
    {
      "type": "output_text",
      "text": "Your seat has been successfully updated to 2B. If there's anything else you need, feel free to ask!",
      "annotations": []
    }
  ]
}
#>

# here, our flow is completed


# ---------------------------------
# Starting sencond request, asking about allowed bags

$res = Invoke-RestMethod -Method Post -Uri "https://api.openai.com/v1/responses" -Headers $headers -ContentType "application/json; charset=utf-8" -Body (ConvertTo-Json -Depth 100 -InputObject @{
    input        = @(
      @{
        role    = "user"
        content = "lets book a seat"
      },
      @{
        type      = "function_call"
        id        = "fc_67dd454a755c819285f15face0783c1b02e59d3f1f3c7ab8"
        call_id   = "call_VbNO0xX5vd4a6RfonLs1A0nw"
        name      = "transfer_to_seat_booking_agent"
        arguments = "{}"
        status    = "completed"
      },
      @{
        call_id = "call_VbNO0xX5vd4a6RfonLs1A0nw"
        output  = "{`"assistant`": `"Seat Booking Agent`"}"
        type    = "function_call_output"
      },
      @{
        type    = "message"
        id      = "msg_67dd482c2c3c8192a9adda691b9d113502e59d3f1f3c7ab8"
        status  = "completed"
        role    = "assistant"
        content = @(
          @{
            type        = "output_text"
            text        = "Sure, I can help with that. Could you please provide your confirmation number?"
            annotations = @()
          }
        )
      },
      @{
        role    = "user"
        content = "123"
      },
      @{
        type    = "message"
        id      = "msg_67dd490980dc8192ae78d48fb3db352302e59d3f1f3c7ab8"
        status  = "completed"
        role    = "assistant"
        content = @(
          @{
            type        = "output_text"
            text        = "Thank you. What seat number would you like to update to?"
            annotations = @()
          }
        )
      },
      @{
        role    = "user"
        content = "2B"
      },
      @{
        type      = "function_call"
        id        = "fc_67dd4d8eb0948192b3c8e6f1abb7d8e502e59d3f1f3c7ab8"
        call_id   = "call_ObtbCAvAuzEuCPgIwpE2awUe"
        name      = "update_seat"
        arguments = "{`"confirmation_number`":`"123`",`"new_seat`":`"2B`"}"
        status    = "completed"
      },
      @{
        call_id = "call_ObtbCAvAuzEuCPgIwpE2awUe"
        output  = "Updated seat to 2B for confirmation number 123"
        type    = "function_call_output"
      },
      # append previous response as is
      @{
        type    = "message"
        id      = "msg_67dd4e954c508192be7923a02976bbc302e59d3f1f3c7ab8"
        status  = "completed"
        role    = "assistant"
        content = @(
          @{
            type        = "output_text"
            text        = "Your seat has been successfully updated to 2B. If there's anything else you need, feel free to ask!"
            annotations = @()
          }
        )
      },
      # add new user input - aka starting new flow
      @{
        role    = "user"
        content = "how many bags can i bring?"
      }
    )
    model        = "gpt-4o"
    include      = @()
    instructions = $seatBookingAgentInstructions
    stream       = $false
    tools        = $seatBookingAgentTools # note: we are still in seat booking agent context
  })

$res.output | ConvertTo-Json -Depth 100
<#
{
  "type": "function_call",
  "id": "fc_67dd4fbd27c88192856f6e80de5f47bb02e59d3f1f3c7ab8",
  "call_id": "call_Z3Dth36cDDsSAbsQuKeVzVz3",
  "name": "transfer_to_triage_agent",
  "arguments": "{}",
  "status": "completed"
}
#>

# note: because this request can not be handled by seat booking agent, and there is `transfer_to_triage_agent` model chooses to call it
# transfer_to_triage_agent is an fake function, that will switch to triage agent


# ---------------------------------
# once received this switch request we will send one more request
# with triage instructions and tools

$res = Invoke-RestMethod -Method Post -Uri "https://api.openai.com/v1/responses" -Headers $headers -ContentType "application/json; charset=utf-8" -Body (ConvertTo-Json -Depth 100 -InputObject @{
    input        = @(
      @{
        role    = "user"
        content = "lets book a seat"
      },
      @{
        type      = "function_call"
        id        = "fc_67dd454a755c819285f15face0783c1b02e59d3f1f3c7ab8"
        call_id   = "call_VbNO0xX5vd4a6RfonLs1A0nw"
        name      = "transfer_to_seat_booking_agent"
        arguments = "{}"
        status    = "completed"
      },
      @{
        call_id = "call_VbNO0xX5vd4a6RfonLs1A0nw"
        output  = "{`"assistant`": `"Seat Booking Agent`"}"
        type    = "function_call_output"
      },
      @{
        type    = "message"
        id      = "msg_67dd482c2c3c8192a9adda691b9d113502e59d3f1f3c7ab8"
        status  = "completed"
        role    = "assistant"
        content = @(
          @{
            type        = "output_text"
            text        = "Sure, I can help with that. Could you please provide your confirmation number?"
            annotations = @()
          }
        )
      },
      @{
        role    = "user"
        content = "123"
      },
      @{
        type    = "message"
        id      = "msg_67dd490980dc8192ae78d48fb3db352302e59d3f1f3c7ab8"
        status  = "completed"
        role    = "assistant"
        content = @(
          @{
            type        = "output_text"
            text        = "Thank you. What seat number would you like to update to?"
            annotations = @()
          }
        )
      },
      @{
        role    = "user"
        content = "2B"
      },
      @{
        type      = "function_call"
        id        = "fc_67dd4d8eb0948192b3c8e6f1abb7d8e502e59d3f1f3c7ab8"
        call_id   = "call_ObtbCAvAuzEuCPgIwpE2awUe"
        name      = "update_seat"
        arguments = "{`"confirmation_number`":`"123`",`"new_seat`":`"2B`"}"
        status    = "completed"
      },
      @{
        call_id = "call_ObtbCAvAuzEuCPgIwpE2awUe"
        output  = "Updated seat to 2B for confirmation number 123"
        type    = "function_call_output"
      },
      @{
        type    = "message"
        id      = "msg_67dd4e954c508192be7923a02976bbc302e59d3f1f3c7ab8"
        status  = "completed"
        role    = "assistant"
        content = @(
          @{
            type        = "output_text"
            text        = "Your seat has been successfully updated to 2B. If there's anything else you need, feel free to ask!"
            annotations = @()
          }
        )
      },
      @{
        role    = "user"
        content = "how many bags can i bring?"
      },
      # append previous response as is
      @{
        type      = "function_call"
        id        = "fc_67dd4fbd27c88192856f6e80de5f47bb02e59d3f1f3c7ab8"
        call_id   = "call_Z3Dth36cDDsSAbsQuKeVzVz3"
        name      = "transfer_to_triage_agent"
        arguments = "{}"
        status    = "completed"
      },
      # append fake function call result
      @{
        call_id = "call_Z3Dth36cDDsSAbsQuKeVzVz3"
        output  = "{`"assistant`": `"Triage Agent`"}"
        type    = "function_call_output"
      }
    )
    model        = "gpt-4o"
    include      = @()
    instructions = $triageAgentInstructions # note: we have switched instructions from seat booking agent to triage agent
    stream       = $false
    tools        = $triageAgentTools # note: also we have switched tools
  })

$res.output | ConvertTo-Json -Depth 100
<#
{
  "type": "function_call",
  "id": "fc_67dd5104dd0881928729621749c5d2e502e59d3f1f3c7ab8",
  "call_id": "call_lmAIldqhqiGafeEDXgd1dIfD",
  "name": "transfer_to_faq_agent",
  "arguments": "{}",
  "status": "completed"
}
#>

# note: triage agent desided to switch us to faq agent, so we will make one more request
# with faq agent instructions and tools


# ---------------------------------

$res = Invoke-RestMethod -Method Post -Uri "https://api.openai.com/v1/responses" -Headers $headers -ContentType "application/json; charset=utf-8" -Body (ConvertTo-Json -Depth 100 -InputObject @{
    input        = @(
      @{
        role    = "user"
        content = "lets book a seat"
      },
      @{
        type      = "function_call"
        id        = "fc_67dd454a755c819285f15face0783c1b02e59d3f1f3c7ab8"
        call_id   = "call_VbNO0xX5vd4a6RfonLs1A0nw"
        name      = "transfer_to_seat_booking_agent"
        arguments = "{}"
        status    = "completed"
      },
      @{
        call_id = "call_VbNO0xX5vd4a6RfonLs1A0nw"
        output  = "{`"assistant`": `"Seat Booking Agent`"}"
        type    = "function_call_output"
      },
      @{
        type    = "message"
        id      = "msg_67dd482c2c3c8192a9adda691b9d113502e59d3f1f3c7ab8"
        status  = "completed"
        role    = "assistant"
        content = @(
          @{
            type        = "output_text"
            text        = "Sure, I can help with that. Could you please provide your confirmation number?"
            annotations = @()
          }
        )
      },
      @{
        role    = "user"
        content = "123"
      },
      @{
        type    = "message"
        id      = "msg_67dd490980dc8192ae78d48fb3db352302e59d3f1f3c7ab8"
        status  = "completed"
        role    = "assistant"
        content = @(
          @{
            type        = "output_text"
            text        = "Thank you. What seat number would you like to update to?"
            annotations = @()
          }
        )
      },
      @{
        role    = "user"
        content = "2B"
      },
      @{
        type      = "function_call"
        id        = "fc_67dd4d8eb0948192b3c8e6f1abb7d8e502e59d3f1f3c7ab8"
        call_id   = "call_ObtbCAvAuzEuCPgIwpE2awUe"
        name      = "update_seat"
        arguments = "{`"confirmation_number`":`"123`",`"new_seat`":`"2B`"}"
        status    = "completed"
      },
      @{
        call_id = "call_ObtbCAvAuzEuCPgIwpE2awUe"
        output  = "Updated seat to 2B for confirmation number 123"
        type    = "function_call_output"
      },
      @{
        type    = "message"
        id      = "msg_67dd4e954c508192be7923a02976bbc302e59d3f1f3c7ab8"
        status  = "completed"
        role    = "assistant"
        content = @(
          @{
            type        = "output_text"
            text        = "Your seat has been successfully updated to 2B. If there's anything else you need, feel free to ask!"
            annotations = @()
          }
        )
      },
      @{
        role    = "user"
        content = "how many bags can i bring?"
      },
      @{
        type      = "function_call"
        id        = "fc_67dd4fbd27c88192856f6e80de5f47bb02e59d3f1f3c7ab8"
        call_id   = "call_Z3Dth36cDDsSAbsQuKeVzVz3"
        name      = "transfer_to_triage_agent"
        arguments = "{}"
        status    = "completed"
      },
      @{
        call_id = "call_Z3Dth36cDDsSAbsQuKeVzVz3"
        output  = "{`"assistant`": `"Triage Agent`"}"
        type    = "function_call_output"
      },
      # append previous response as is
      @{
        type      = "function_call"
        id        = "fc_67dd5104dd0881928729621749c5d2e502e59d3f1f3c7ab8"
        call_id   = "call_lmAIldqhqiGafeEDXgd1dIfD"
        name      = "transfer_to_faq_agent"
        arguments = "{}"
        status    = "completed"
      },
      # append fake function call result
      @{
        call_id = "call_lmAIldqhqiGafeEDXgd1dIfD"
        output  = "{`"assistant`": `"FAQ Agent`"}"
        type    = "function_call_output"
      }
    )
    model        = "gpt-4o"
    include      = @()
    instructions = $faqAgentInstructions # note: we have switched instructions from triage agent to gaq agent
    stream       = $false
    tools        = $faqAgentTools # note: also we have switched tools
  })

$res.output | ConvertTo-Json -Depth 100
<#
{
  "type": "function_call",
  "id": "fc_67dd5351d99881929d5374c1d8cb101502e59d3f1f3c7ab8",
  "call_id": "call_t7a2MbLYhD2jyLYZrD0wsYMV",
  "name": "faq_lookup_tool",
  "arguments": "{\"question\":\"how many bags can i bring?\"}",
  "status": "completed"
}
#>

# note: because of tools, our model recognized call to faq lookup and tries to cal that function

# ---------------------------------
# after calling faq lookup, we will receive response with answer which we pass back to the model

$res = Invoke-RestMethod -Method Post -Uri "https://api.openai.com/v1/responses" -Headers $headers -ContentType "application/json; charset=utf-8" -Body (ConvertTo-Json -Depth 100 -InputObject @{
    input        = @(
      @{
        role    = "user"
        content = "lets book a seat"
      },
      @{
        type      = "function_call"
        id        = "fc_67dd454a755c819285f15face0783c1b02e59d3f1f3c7ab8"
        call_id   = "call_VbNO0xX5vd4a6RfonLs1A0nw"
        name      = "transfer_to_seat_booking_agent"
        arguments = "{}"
        status    = "completed"
      },
      @{
        call_id = "call_VbNO0xX5vd4a6RfonLs1A0nw"
        output  = "{`"assistant`": `"Seat Booking Agent`"}"
        type    = "function_call_output"
      },
      @{
        type    = "message"
        id      = "msg_67dd482c2c3c8192a9adda691b9d113502e59d3f1f3c7ab8"
        status  = "completed"
        role    = "assistant"
        content = @(
          @{
            type        = "output_text"
            text        = "Sure, I can help with that. Could you please provide your confirmation number?"
            annotations = @()
          }
        )
      },
      @{
        role    = "user"
        content = "123"
      },
      @{
        type    = "message"
        id      = "msg_67dd490980dc8192ae78d48fb3db352302e59d3f1f3c7ab8"
        status  = "completed"
        role    = "assistant"
        content = @(
          @{
            type        = "output_text"
            text        = "Thank you. What seat number would you like to update to?"
            annotations = @()
          }
        )
      },
      @{
        role    = "user"
        content = "2B"
      },
      @{
        type      = "function_call"
        id        = "fc_67dd4d8eb0948192b3c8e6f1abb7d8e502e59d3f1f3c7ab8"
        call_id   = "call_ObtbCAvAuzEuCPgIwpE2awUe"
        name      = "update_seat"
        arguments = "{`"confirmation_number`":`"123`",`"new_seat`":`"2B`"}"
        status    = "completed"
      },
      @{
        call_id = "call_ObtbCAvAuzEuCPgIwpE2awUe"
        output  = "Updated seat to 2B for confirmation number 123"
        type    = "function_call_output"
      },
      @{
        type    = "message"
        id      = "msg_67dd4e954c508192be7923a02976bbc302e59d3f1f3c7ab8"
        status  = "completed"
        role    = "assistant"
        content = @(
          @{
            type        = "output_text"
            text        = "Your seat has been successfully updated to 2B. If there's anything else you need, feel free to ask!"
            annotations = @()
          }
        )
      },
      @{
        role    = "user"
        content = "how many bags can i bring?"
      },
      @{
        type      = "function_call"
        id        = "fc_67dd4fbd27c88192856f6e80de5f47bb02e59d3f1f3c7ab8"
        call_id   = "call_Z3Dth36cDDsSAbsQuKeVzVz3"
        name      = "transfer_to_triage_agent"
        arguments = "{}"
        status    = "completed"
      },
      @{
        call_id = "call_Z3Dth36cDDsSAbsQuKeVzVz3"
        output  = "{`"assistant`": `"Triage Agent`"}"
        type    = "function_call_output"
      },
      @{
        type      = "function_call"
        id        = "fc_67dd5104dd0881928729621749c5d2e502e59d3f1f3c7ab8"
        call_id   = "call_lmAIldqhqiGafeEDXgd1dIfD"
        name      = "transfer_to_faq_agent"
        arguments = "{}"
        status    = "completed"
      },
      @{
        call_id = "call_lmAIldqhqiGafeEDXgd1dIfD"
        output  = "{`"assistant`": `"FAQ Agent`"}"
        type    = "function_call_output"
      },
      # append previous message as is
      @{
        type      = "function_call"
        id        = "fc_67dd5351d99881929d5374c1d8cb101502e59d3f1f3c7ab8"
        call_id   = "call_t7a2MbLYhD2jyLYZrD0wsYMV"
        name      = "faq_lookup_tool"
        arguments = "{`"question`":`"how many bags can i bring?`"}"
        status    = "completed"
      },
      # as well as the function call result
      @{
        call_id = "call_t7a2MbLYhD2jyLYZrD0wsYMV"
        output  = "You are allowed to bring one bag on the plane. It must be under 50 pounds and 22 inches x 14 inches x 9 inches."
        type    = "function_call_output"
      }
    )
    model        = "gpt-4o"
    include      = @()
    instructions = $faqAgentInstructions
    stream       = $false
    tools        = $faqAgentTools
  })

$res.output | ConvertTo-Json -Depth 100
<#
{
  "type": "message",
  "id": "msg_67dd54421b1c81929a8defdad31cc17c02e59d3f1f3c7ab8",
  "status": "completed",
  "role": "assistant",
  "content": [
    {
      "type": "output_text",
      "text": "You are allowed to bring one bag on the plane, which must be under 50 pounds and 22 inches x 14 inches x 9 inches in size. If you have more questions, feel free to ask!",
      "annotations": []
    }
  ]
}
#>

# note: having the response from function call, model uses it to respond to user
